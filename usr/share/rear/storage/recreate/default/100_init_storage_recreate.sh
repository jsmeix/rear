
# storage/recreate/default/100_init_storage_recreate.sh
# initializes directories and files when storage gets recreated

readonly STORAGE_SAVED_DIR="$VAR_DIR/storage/saved"
readonly STORAGE_SAVED_LSBLK_FILE="$STORAGE_SAVED_DIR/lsblk.output"
readonly STORAGE_SAVED_PARTED_FILE="$STORAGE_SAVED_DIR/parted.output"
readonly STORAGE_SAVED_MDADM_FILE="$STORAGE_SAVED_DIR/mdadm.output"

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
    local timeout=10
    local countdown
    for countdown in $( seq $timeout -1 0 ) ; do
        test -b $device_node && return 0
        # Skip to show the message for the very first time (i.e. wait the first second silently)
        # to avoid needless user messages when device nodes appear within less than one second:
        test "$timeout" = "$countdown" || LogPrintError "Waiting for $device_node to appear ($countdown)"
        sleep 1
    done
    test -b $device_node && return 0
    LogPrintError "No $device_node had appeared after waiting for $timeout seconds"
    return 1
}

# For all 'disk' type kernel device names in STORAGE_SAVED_LSBLK_FILE
# create partitions according to the 'parted' output in STORAGE_SAVED_PARTED_FILE:
local disk_kname partition_number missing_partition
for disk_kname in $( grep 'TYPE="disk"' $STORAGE_SAVED_LSBLK_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    Log "Creating partitions on $disk_kname according to $STORAGE_SAVED_PARTED_FILE"
    if ! grep -q "^$disk_kname " $STORAGE_SAVED_PARTED_FILE ; then
        LogPrintError "Cannot create partitions on $disk_kname (no info found in $STORAGE_SAVED_PARTED_FILE)"
        continue
    fi
    if ! grep -q "^$disk_kname BYT;$" $STORAGE_SAVED_PARTED_FILE ; then
        BugError "Cannot create partitions on $disk_kname (only parted output with 'BYT' unit is currently supported)"
        continue
    fi
    if ! grep -q "^$disk_kname $disk_kname:.*:gpt:.*;$" $STORAGE_SAVED_PARTED_FILE ; then
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
        if ! grep -q "^$disk_kname $partition_number:" $STORAGE_SAVED_PARTED_FILE ; then
            missing_partition="yes"
            continue
        fi
        # When there was at least one missing partition and now we found one with higher number the partitions are not consecutive:
        is_true $missing_partition && BugError "Failed to create partitions on $disk_kname (only consecutive partitions are currently supported)"
        # Currently only the usual GPT up to 128 partitions is supported:
        test "129" = "$partition_number" && BugError "Failed to create partitions on $disk_kname (only up to 128 partitions are currently supported)"


    done

done


# Save 'lsblk' output in human readable form and in computer readable form:
has_binary lsblk || Error "The 'lsblk' command is required for saving storage info"
REQUIRED_PROGS+=( lsblk )
readonly STORAGE_RECREATED_LSBLK_FILE="$STORAGE_RECREATED_DIR/lsblk.output"
Log "Saving 'lsblk' output to $STORAGE_RECREATED_LSBLK_FILE"
# See lib/layout-functions.sh how DATE is set: DATE=$( date +%Y%m%d%H%M%S )
echo "'lsblk' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_RECREATED_LSBLK_FILE
# Have the human readable 'lsblk' output as header comment
# so that it is easier to make sense of the values in computer readable form.
# First try the command
#   lsblk -ipo NAME,KNAME,PKNAME,TRAN,TYPE,FSTYPE,SIZE,MOUNTPOINT
# but on older systems (like SLES11) that do not support all that lsblk things
# try the simpler command
#   lsblk -io NAME,KNAME,FSTYPE,SIZE,MOUNTPOINT
# and as fallback try 'lsblk -i' and finally call plain 'lsblk' (and hope for the best):
{ lsblk -ipo NAME,KNAME,PKNAME,TRAN,TYPE,FSTYPE,SIZE,MOUNTPOINT || lsblk -io NAME,KNAME,FSTYPE,SIZE,MOUNTPOINT || lsblk -i || lsblk ; } >>$STORAGE_RECREATED_LSBLK_FILE
# Make all lines up to now as header comments:
sed -i -e 's/^/# /' $STORAGE_RECREATED_LSBLK_FILE
# Save 'lsblk' output in computer readable form (size as byte values):
{ lsblk -bpPO ; } >>$STORAGE_RECREATED_LSBLK_FILE || Error "Required command 'lsblk -bpPO' failed"

# For all 'disk' type kernel device names in the 'lsblk' output
# save the 'parted' output in human readable form and in computer readable form:
has_binary parted || Error "The 'parted' command is required for saving storage info"
REQUIRED_PROGS+=( parted )
readonly STORAGE_RECREATED_PARTED_FILE="$STORAGE_RECREATED_DIR/parted.output"
echo "# 'parted' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_RECREATED_PARTED_FILE
{ echo ' Brief description of the "parted -m" machine parseable output format, cf.
 https://alioth-lists.debian.net/pipermail/parted-devel/2006-December/000573.html
 All lines end with a semicolon (;)
 The first line indicates the units in which the output is expressed.
 CHS, CYL and BYT stands for CHS, Cylinder and Bytes respectively.
 The second line is made of disk information in the following format:
 "path":"size":"transport-type":"logical-sector-size":"physical-sector-size":"partition-table-type":"model-name";
 If the first line was either CYL or CHS, the next line will contain
 information on no. of cylinders, heads, sectors and cylinder size.
 Partition information begins from the next line. This is of the format:
 (for BYT) "number":"begin":"end":"size":"filesystem-type":"partition-name":"flags-set";
 (for CHS/CYL) "number":"begin":"end":"filesystem-type":"partition-name":"flags-set"; ' | sed -e 's/^/#/' ; } >>$STORAGE_RECREATED_PARTED_FILE
# A 'lsblk -bpPO' output line looks like (excerpts):
#   NAME="/dev/sda" KNAME="/dev/sda" ... TYPE="disk" ... PKNAME="" ...
# so we grep for ' KNAME=...' with a leading blank to exclude 'PKNAME' and
# from the result KNAME="/dev/sda" we cut the second field /dev/sda with " field delimiter:
local disk_kname
for disk_kname in $( grep 'TYPE="disk"' $STORAGE_RECREATED_LSBLK_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    Log "Saving 'parted' output for $disk_kname to $STORAGE_RECREATED_PARTED_FILE"
    # Have the human readable 'parted' output as header comment (with discarded empty lines)
    # so that it is easier to make sense of the values in computer readable form.
    { parted -s $disk_kname unit MiB print | grep -v '^$' | sed -e 's/^/# /' ; } >>$STORAGE_RECREATED_PARTED_FILE
    # Save the 'parted' output in computer readable form (with byte values)
    # with the kernel device name as line prefix added.
    # Using # as sed 's' command delimiter because / is in $disk_kname (e.g. /dev/sda):
    if  ! { parted -sm $disk_kname unit B print | sed -e "s#^#$disk_kname #" ; } >>$STORAGE_RECREATED_PARTED_FILE ; then
        Error "Required command 'parted -sm $disk_kname unit B print' failed"
    fi
done

# Save the 'mdadm' output for MD devices aka Linux Software RAID:
readonly STORAGE_RECREATED_MDADM_FILE="$STORAGE_RECREATED_DIR/mdadm.output"
if has_binary mdadm ; then
    # Regardless whether or not MD devices are actually currently used,
    # when the 'mdadm' command is there we save its output even if it is empty
    # so that it is documented when there is no 'mdadm' output but also
    # if there is no longer 'mdadm' output (e.g. when MD devices had been removed).
    REQUIRED_PROGS+=( mdadm )
    Log "Saving 'mdadm' output to $STORAGE_RECREATED_MDADM_FILE"
    echo "# 'mdadm' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_RECREATED_MDADM_FILE
    { mdadm --detail --scan ; } >>$STORAGE_RECREATED_MDADM_FILE || Error "Required command 'mdadm --detail --scan' failed"
    # A normal 'mdadm --detail --scan' output line looks like:
    #   ARRAY /dev/md/arrayname metadata=1.0 name=hostname:arrayname UUID=43f60cda:d221604f:5d3438a3:8c225f70
    # so we grep for '^ARRAY ' to avoid possible unwanted lines and
    # from the result we cut the second field /dev/md/arrayname with ' ' field delimiter:
    local md_device
    for md_device in $( grep '^ARRAY ' $STORAGE_RECREATED_MDADM_FILE | cut -d ' ' -f2 ) ; do
        # For each ARRAY MD device in STORAGE_RECREATED_MDADM_FILE save the details
        # with the ARRAY MD device name as line prefix added (and discarded empty lines).
        # Using # as sed 's' command delimiter because / is in $md_device (like /dev/md/arrayname):
        if ! { mdadm --detail $md_device | grep -v '^$' | sed -e "s#^#$md_device #" ; } >>$STORAGE_RECREATED_MDADM_FILE ; then
            Error "Required command 'mdadm --detail $md_device' failed"
        fi
    done
else
    # When there are 'raid[0-9]*' TYPE entries in the 'lsblk' output
    # there are MD devices so it is an error when there is no 'mdadm' command:
    grep -q 'TYPE="raid[^"]*"' $STORAGE_RECREATED_LSBLK_FILE && Error "The 'mdadm' command is required for saving storage info"
    # Document that there is no 'mdadm' command (also to overwrite possibly outdated STORAGE_RECREATED_MDADM_FILE content):
    echo "# No 'mdadm' output because there is no 'mdadm' command dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_RECREATED_MDADM_FILE
fi

unset -f wait_for_device_node

Error "End at ${BASH_SOURCE[0]}"

