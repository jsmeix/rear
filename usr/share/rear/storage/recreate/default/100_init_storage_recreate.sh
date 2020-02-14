
# storage/recreate/default/100_init_storage_recreate.sh
# initializes directories and files when storage gets recreated

readonly STORAGE_SAVED_DIR="$VAR_DIR/storage/saved"
readonly STORAGE_LSBLK_OUTPUT_FILE="$STORAGE_SAVED_DIR/lsblk.output"
readonly STORAGE_PARTED_OUTPUT_FILE="$STORAGE_SAVED_DIR/parted.output"
readonly STORAGE_MDADM_OUTPUT_FILE="$STORAGE_SAVED_DIR/mdadm.output"

LogPrint "Recreating storage according to the files in $STORAGE_SAVED_DIR"

Debug "Creating directories for storage recreation (when not existing)"
readonly STORAGE_RECREATING_DIR="$VAR_DIR/storage/recreating"
mkdir -p $v "$STORAGE_RECREATING_DIR"
readonly STORAGE_RECREATED_DIR="$VAR_DIR/storage/recreated"
mkdir -p $v "$STORAGE_RECREATED_DIR"

# Wipe existing partitions from all disks in reverse ordering, for example
# first /dev/sdb2 then /dev/sdb1 then /dev/sdb then /dev/sda2 then /dev/sda1 finally /dev/sda
# cf. https://github.com/rear/rear/issues/799
local disk_or_part_kname
for disk_or_part_kname in $( lsblk -ipo TYPE,KNAME | egrep '^disk |^part ' | tac | tr -s ' ' |  cut -d ' ' -f2 ) ; do
    wipefs -a -f $disk_or_part_kname && LogPrint "Wiped $disk_or_part_kname by 'wipefs -a -f'" || LogPrintError "Failed to wipe $disk_or_part_kname by 'wipefs -a -f'"
done

# Cf. https://github.com/rear/rear/issues/791
function wait_for_device_node () {
    local device_node=$1
    test "$device_node" || BugError "wait_for_device_node() called without device_node argument"
    local timeout=$2
    is_positive_integer $timeout 1>/dev/null || timeout=10
    local countdown
    for countdown in $( seq $timeout -1 0 ) ; do
        test -b $device_node && return 0
        # Skip to show the message for the very first time (i.e. wait the first second silently)
        # to avoid needless user messages when device nodes appear within less than one second.
        # Using LogPrintError because waiting for more than one second may indicate an error:
        test "$timeout" = "$countdown" || LogPrintError "Waiting for $device_node to appear ($countdown)"
        sleep 1
    done
    test -b $device_node && return 0
    LogPrintError "No $device_node had appeared after waiting for $timeout seconds"
    return 1
}

# For all 'disk' type kernel device names in STORAGE_LSBLK_OUTPUT_FILE
# create partitions according to the 'parted' output in STORAGE_PARTED_OUTPUT_FILE:
local disk_kname partition_number partition_parted_line missing_partition
local partition_start_byte partition_start_number partition_end_byte partition_end_number partition_filesystem_type gpt_partition_name
local partition_flags partition_flag
for disk_kname in $( grep 'TYPE="disk"' $STORAGE_LSBLK_OUTPUT_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    Log "Creating partitions on $disk_kname according to $STORAGE_PARTED_OUTPUT_FILE"
    if ! grep -q "^$disk_kname " $STORAGE_PARTED_OUTPUT_FILE ; then
        LogPrintError "Cannot create partitions on $disk_kname (no info found in $STORAGE_PARTED_OUTPUT_FILE)"
        continue
    fi
    if ! grep -q "^$disk_kname BYT;$" $STORAGE_PARTED_OUTPUT_FILE ; then
        BugError "Cannot create partitions on $disk_kname (only parted output with 'BYT' unit is currently supported)"
        continue
    fi
    if ! grep -q "^$disk_kname $disk_kname:.*:gpt:.*;$" $STORAGE_PARTED_OUTPUT_FILE ; then
        BugError "Cannot create partitions on $disk_kname (only GPT partitioning is currently supported)"
        continue
    fi
    if ! wait_for_device_node $disk_kname ; then
        LogPrintError "Cannot create partitions on $disk_kname (it does not exist or it did not appear)"
        continue
    fi
    # Create GPT partitioning from scratch:
    if ! parted -s $disk_kname mklabel gpt ; then
        LogPrintError "Failed to create GPT on $disk_kname ('parted -s $disk_kname mklabel gpt' failed)"
        continue
    fi
    # Create partitions:
    missing_partition="no"
    for partition_number in $( seq 1 129 ) ; do
        if ! partition_parted_line=$( grep "^$disk_kname $partition_number:" $STORAGE_PARTED_OUTPUT_FILE ) ; then
            missing_partition="yes"
            # All is o.k. when from a last existing partition number N
            # all further partitions are missing up to partition number 128:
            test "128" = "$partition_number" && break
            # Continue testing to find if a subsequent non consecutive partition > N exists:
            continue
        fi
        # When there was at least one missing partition and now we found one with higher number the partitions are not consecutive:
        is_true $missing_partition && BugError "Failed to create partitions on $disk_kname (only consecutive partitions are currently supported)"
        # Currently only the usual (i.e. minimal) GPT up to 128 partitions is supported:
        test "129" = "$partition_number" && BugError "Failed to create partitions on $disk_kname (only up to 128 partitions are currently supported)"
        # Get the values from the 'parted -m' output line which look for example like
        #   /dev/sda 5:17180917760B:19328401407B:2147483648B:ext2:sda5:raid, legacy_boot;
        # with the following syntax for 'parted -m' output for "BYT" with our added disk_kname prefix
        #   disk_kname "number":"begin":"end":"size":"filesystem-type":"partition-name":"flags-set";
        partition_start_byte=$( cut -d ':' -f2 <<<"$partition_parted_line" )
        partition_start_number=${partition_start_byte%%[^0-9]*}
        if ! is_positive_integer $partition_start_number 1>/dev/null ; then
            LogPrintError "Cannot create partition $partition_number on $disk_kname (partition start $partition_start_number no positive integer)"
            continue
        fi
        partition_end_byte=$( cut -d ':' -f3 <<<"$partition_parted_line" )
        partition_end_number=${partition_end_byte%%[^0-9]*}
        if ! is_positive_integer $partition_end_number 1>/dev/null ; then 
            LogPrintError "Cannot create partition $partition_number on $disk_kname (partition end $partition_end_number no positive integer)"
            continue
        fi
        if ! test $partition_end_number -gt $partition_start_number ; then 
            LogPrintError "Cannot create partition $partition_number on $disk_kname (partition end $partition_end_number <= $partition_start_number)"
            continue
        fi
        partition_filesystem_type=$( cut -d ':' -f5 <<<"$partition_parted_line" )
        # The GNU Parted User Manual section about parted's 'mkpart' command
        # at https://www.gnu.org/software/parted/manual/parted.html#mkpart
        # reads "fs-type is required for data partitions (i.e., non-extended partitions)"
        # so we have to set a fallback value when $partition_filesystem_type is empty:
        test "$partition_filesystem_type" || partition_filesystem_type="ext2"
        gpt_partition_name=$( cut -d ':' -f6 <<<"$partition_parted_line" )
        # The GNU Parted User Manual section about parted's 'mkpart' command
        # at https://www.gnu.org/software/parted/manual/parted.html#mkpart
        # reads "A name must be specified for a ‘gpt’ partition table"
        # so we have to set a fallback value when $gpt_partition_name is empty:
        test "$gpt_partition_name" || gpt_partition_name="$( basename $disk_kname )$partition_number"
        if ! parted -s $disk_kname mkpart "$gpt_partition_name" "$partition_filesystem_type" $partition_start_byte $partition_end_byte ; then
            LogPrintError "Failed to create partition $partition_number on $disk_kname ('parted -s $disk_kname mkpart '$gpt_partition_name''$partition_filesystem_type' $partition_start_byte $partition_end_byte' failed)"
            continue
        fi
        # For example the flags-set entry in the 'parted -m' output line is
        #   raid, legacy_boot;
        # (cf. the 'parted -m' output line example above).
        # According to the GNU Parted User Manual section about parted's 'set' command
        # at https://www.gnu.org/software/parted/manual/parted.html#set
        # the possible flags only for GPT partitions are
        #   bios_grub legacy_boot msftdata
        # and only for legacy MS-DOS partitions
        #   boot lba hidden raid LVM PALO DIAG
        # and for both GPT and MS-DOS partitions
        #   msftres irst esp PREP
        # so all flags consist of a single word (i.e. no blank characters in a flag name)
        # so that we can translate e.g. "raid, legacy_boot;" into "raid legacy_boot":
        partition_flags=$( cut -d ':' -f7 <<<"$partition_parted_line" | tr -d ',;' )
        # When $partition_flags is empty the 'for' loop does nothing:
        for partition_flag in $partition_flags ; do
            if ! parted -s $disk_kname set $partition_number $partition_flag on ; then
                LogPrintError "Failed to set partition flag $partition_flag on partition $partition_number on $disk_kname ('parted -s $disk_kname set $partition_number $partition_flag on' failed)"
                continue
            fi
        done
    done
done

# Create MD devices aka Linux Software RAID:
# For all 'raid...' type kernel device names in STORAGE_LSBLK_OUTPUT_FILE
# create MD devices according to the 'mdadm' output in STORAGE_MDADM_OUTPUT_FILE:
local raid_kname
for raid_kname in $( grep 'TYPE="raid.*"' $STORAGE_LSBLK_OUTPUT_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    Log "Creating MD devices for $raid_kname according to $STORAGE_MDADM_OUTPUT_FILE"
    if ! grep -q "^$raid_kname " $STORAGE_MDADM_OUTPUT_FILE ; then
        LogPrintError "Cannot create MD devices for $raid_kname (no info found in $STORAGE_MDADM_OUTPUT_FILE)"
        continue
    fi


done

unset -f wait_for_device_node

Error "End at ${BASH_SOURCE[0]}"

