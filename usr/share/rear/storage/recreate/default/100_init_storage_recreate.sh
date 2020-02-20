
# storage/recreate/default/100_init_storage_recreate.sh
# initializes directories and files when storage gets recreated

readonly STORAGE_SAVED_DIR="$VAR_DIR/storage/saved"
readonly STORAGE_BLOCKDEV_SYMLINKS_FILE="$STORAGE_SAVED_DIR/block_device.symlinks"
readonly STORAGE_LSBLK_OUTPUT_FILE="$STORAGE_SAVED_DIR/lsblk.output"
readonly STORAGE_PARTED_OUTPUT_FILE="$STORAGE_SAVED_DIR/parted.output"
readonly STORAGE_MDADM_OUTPUT_FILE="$STORAGE_SAVED_DIR/mdadm.output"
readonly STORAGE_LVM_OUTPUT_FILE="$STORAGE_SAVED_DIR/lvm.output"

LogPrint "Recreating storage according to the files in $STORAGE_SAVED_DIR"

Debug "Creating directories for storage recreation (when not existing)"
readonly STORAGE_RECREATING_DIR="$VAR_DIR/storage/recreating"
mkdir -p $v "$STORAGE_RECREATING_DIR"
readonly RECREATING_LVM_PVS_MAPPING_FILE="$STORAGE_RECREATING_DIR/lvm.PVs.old.new.mapping"
readonly RECREATING_BLOCKDEV_SYMLINKS_FILE="$STORAGE_RECREATING_DIR/block_device.symlinks"
readonly STORAGE_RECREATED_DIR="$VAR_DIR/storage/recreated"
mkdir -p $v "$STORAGE_RECREATED_DIR"

# Cf. https://github.com/rear/rear/issues/2254#issuecomment-545506104
# Output the kernel block device names in var/lib/rear/storage/saved/block_device.symlinks
# that match the argument (separated by each other with newline):
function kernel_block_device_names () {
    local block_device_regexp="$1"
    grep "$block_device_regexp" $STORAGE_BLOCKDEV_SYMLINKS_FILE | cut -d ' ' -f1 | sort -u
}

# Cf. https://github.com/rear/rear/issues/791
function wait_for_device_node () {
    local device_node=$1
    test "$device_node" || BugError "wait_for_device_node() called without device_node argument"
    local timeout=$2
    is_positive_integer $timeout 1>/dev/null || timeout=10
    local countdown
    for countdown in $( seq $timeout -1 0 ) ; do
        # 'test -b device_node' is also 'true' when device_node is a symlink to a block device:
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

# Output symlinks in /dev/ that point to kernel block device node names.
# Each symlink is on a separated line that has the form
#    /dev/kernel_block_device_node /dev/symlink_path_that_points_to_kernel_block_device_node
# and the lines are sorted (so same kernel block device nodes appear next to each other):
function block_device_symlinks () {
    { local symlink symlink_target
      for symlink in $( find /dev -type l ) ; do
          symlink_target=$( readlink -e $symlink )
          test -b "$symlink_target" || continue
          echo "$symlink_target $symlink"
      done | sort
    } 2>>/dev/$DISPENSABLE_OUTPUT_DEV
}

# When there are TYPE="raid.*" devices in STORAGE_LSBLK_OUTPUT_FILE
# shut down all MD devices aka Linux Software RAID arrays that can be shut down (i.e. that are not currently in use):
if grep -q 'TYPE="raid.*"' $STORAGE_LSBLK_OUTPUT_FILE ; then
    LogPrint "Shutting down MD devices aka software RAID arrays ('lsblk' shows TYPE 'raid.*' devices)"
    mdadm --stop --scan || LogPrintError "Cannot shut down software RAID arrays ('mdadm --stop --scan' failed)"
fi

# Wipe existing partitions from all disks in reverse ordering,
# first partitions in reverse ordering
# for example /dev/sdb2 then /dev/sdb1 then /dev/sda3 then /dev/sda2 then /dev/sda1
# then disks in reverse ordering
# for example /dev/sdb then /dev/sda
# cf. https://github.com/rear/rear/issues/799
local type kname
for type in part disk ; do
    for kname in $( lsblk -ipo TYPE,KNAME | grep "^$type " | tac | tr -s '[:blank:]' ' ' |  cut -d ' ' -f2 ) ; do
        LogPrint "Wiping $kname by 'wipefs -a -f'"
        wipefs -a -f $kname || LogPrintError "Failed to wipe $kname by 'wipefs -a -f'"
    done
done

# For all 'disk' type kernel device names in STORAGE_LSBLK_OUTPUT_FILE
# create partitions according to the 'parted' output in STORAGE_PARTED_OUTPUT_FILE:
local disk_kname partition_number partition_parted_line missing_partition
local partition_start_byte partition_start_number partition_end_byte partition_end_number partition_filesystem_type gpt_partition_name
local partition_flags partition_flag
for disk_kname in $( grep 'TYPE="disk"' $STORAGE_LSBLK_OUTPUT_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    LogPrint "Creating partitions on $disk_kname according to $STORAGE_PARTED_OUTPUT_FILE ..."
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
        LogPrint "Creating partition $partition_number on $disk_kname"
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
            LogPrintError "Failed to create partition $partition_number on $disk_kname ('parted -s $disk_kname mkpart '$gpt_partition_name' '$partition_filesystem_type' $partition_start_byte $partition_end_byte' failed)"
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
    LogPrint "Created partitions on $disk_kname"
done
# TODO: Verify that for all created partitions a matching kernel block device node exists.
# Cf. the "Verify that the created RAID array device exists" comment below and see also
# the comment for 'block_device_symlinks >$RECREATING_BLOCKDEV_SYMLINKS_FILE' below.
# The problem is that we do not know for sure what the kernel block device node name
# will be for partitions on whatever special kind of 'disk' type devices because
# there are several different ways how kernel block device node names for partitions
# are generated based on the kernel block device node name for its 'disk' device.
# But we cannot call wait_for_device_node() when we do not know what to wait for.
# Perhaps we could rely on what is stored in STORAGE_LSBLK_OUTPUT_FILE for 'part' type devices
# from the original system where "rear mkrescue" had been running that the same must also
# appear on the current (replacement) system where "rear recover" is currently running?
# So for now we sleep 2 seconds and call "udevadm settle" and hope for the best
# (in particular "udevadm settle" may silently wait up to its default timeout value of 120 seconds):
LogPrint "Waiting for 'udevadm settle' to let the kernel block device nodes appear for the created partitions"
sleep 2
udevadm settle

# Create MD devices aka Linux Software RAID:
# For all listed 'ARRAY' device names (symlinks) in STORAGE_MDADM_OUTPUT_FILE
# create MD devices according to the 'mdadm' output in STORAGE_MDADM_OUTPUT_FILE:
local raid_array_name
local mdadm_detail_line extracted_value
local raid_level raid_devices total_devices
local component_devices component_device
LogPrint "Creating MD devices (aka Linux Software RAID) according to $STORAGE_MDADM_OUTPUT_FILE ..."
for raid_array_name in $( grep '^ARRAY ' $STORAGE_MDADM_OUTPUT_FILE | cut -d ' ' -f2 ) ; do
    LogPrint "Creating software RAID $raid_array_name"
    # Minimal 'mdadm' command to create a RAID array:
    #   mdadm --create $raid_array_name --level=$raid_level --raid-devices=$raid_devices $component_devices
    # for example
    #   mdadm --create MyArray --level=raid1 --raid-devices=2 /dev/sda2 /dev/sdb2
    raid_level=""
    raid_devices=""
    total_devices=""
    component_devices=""
    while read mdadm_detail_line ; do
        # Example 'Raid Level' line:
        #          Raid Level : raid1
        # Because things in $(...) run in a subshell we can 'set -o pipefail' therein
        # to find out if the pipe that tries to extract a particular value was successful
        # ('set -o pipefail' is in particular needed to test if 'grep' was successful)
        # and assign the extracted value only if the extraction was successful:
        extracted_value="$( set -o pipefail ; grep 'Raid Level :' <<<"$mdadm_detail_line" | cut -d ':' -f2 | tr -d '[:space:]' )" && raid_level="$extracted_value"
        # Example 'Raid Devices' line:
        #        Raid Devices : 2
        extracted_value="$( set -o pipefail ; grep 'Raid Devices :' <<<"$mdadm_detail_line" | cut -d ':' -f2 | tr -d '[:space:]' )" && raid_devices="$extracted_value"
        # Example 'Total Devices' line:
        #       Total Devices : 3
        extracted_value="$( set -o pipefail ; grep 'Total Devices :' <<<"$mdadm_detail_line" | cut -d ':' -f2 | tr -d '[:space:]' )" && total_devices="$extracted_value"
        # Example lines that list the RAID array devices:
        #      Number   Major   Minor   RaidDevice State
        #         0       8        2        0      active sync   /dev/sda2
        #         1       8       18        1      active sync   /dev/sdb2
        extracted_value="$( set -o pipefail ; grep -o ' /dev/.*' <<<"$mdadm_detail_line" | tr -d '[:space:]' )" && component_devices+=" $extracted_value"
    done < <( grep "^$raid_array_name " $STORAGE_MDADM_OUTPUT_FILE | sed -e "s#^$raid_array_name ##" )
    # Check RAID devices number:
    if ! test $raid_devices -eq $total_devices ; then
        BugError "Cannot create $raid_array_name (RAID devices $raid_devices != $total_devices total devices is currently not supported)"
        continue
    fi
    # Verify that the RAID array component devices exist:
    for component_device in $component_devices ; do
        if ! wait_for_device_node $component_device ; then
            LogPrintError "Cannot create RAID $raid_array_name (needed RAID component device $component_device does not exist or did not appear)"
            continue 2
        fi
    done
    # Create the RAID array.
    # There is no 'mdadm' option to enforce non-interactive mode so we feed 'y' into it to respond positively to all its questions
    # (there is no 'yes' program like /usr/bin/yes in the ReaR recovery system so we feed an unlimited amount of 'y' manually).
    # Without "sleep 1" tens of thousands of '++ true' and '++ echo y' lines would appear in the log in 'set -x' debugscript mode
    # which also indicates that 'mdadm' is needlessly greedy and swallows unlimited amounts of whatever it gets fed via stdin.
    # The while loop dies with exit code 141 which means 141 - 128 = 13 = SIGPIPE when 'mdadm' finishes.
    # The exit code of the pipe is the exit code of its last command so we test the 'mdadm' exit code:
    if ! while true ; do echo 'y' ; sleep 1 ; done | mdadm --create $raid_array_name $verbose --assume-clean --level=$raid_level --raid-devices=$raid_devices $component_devices ; then
         LogPrintError "Failed to create RAID $raid_array_name ('mdadm --create $raid_array_name --assume-clean --level=$raid_level --raid-devices=$raid_devices $component_devices' failed)"
        continue
    fi
    # Verify that the created RAID array device exists.
    # We do that here in particular because the created RAID array device is likely
    # needed later to create a filesystem on it or as a LVM physical volume and
    # here we know what device to wait for so we can call wait_for_device_node for it
    # (cf. the comment for 'block_device_symlinks >$RECREATING_BLOCKDEV_SYMLINKS_FILE' below):
    if ! wait_for_device_node $raid_array_name ; then
        LogPrintError "Failed to create RAID $raid_array_name (RAID device $raid_array_name does not exist or did not appear)"
        continue
    fi
done
LogPrint "Created MD devices"

# Create LVM physical volumes, LVM volume groups, and LVM logical volumes:
local orig_pv_dev orig_pv_dev_symlink
local orig_pv_dev_symlinks=()
local current_targets=()
local current_orig_pv_dev_symlinks_targets=()
local current_target
local current_pv_dev
local pv_uuid
LogPrint "Creating LVM physical volumes, LVM volume groups, and LVM logical volumes according to $STORAGE_LVM_OUTPUT_FILE"

# Creating LVM physical volumes:
cat /dev/null >$RECREATING_LVM_PVS_MAPPING_FILE
# TODO: Here is a problem with delays in udev or in the kernel (cf. https://github.com/rear/rear/issues/791)
# when currently (some) block device symlinks may not yet be there (but may appear later after some time)
# so subsequent things may fail because of not yet existing current block device symlinks.
# But we cannot call wait_for_device_node() here because we do not know what to wait for.
# In particular we cannot call wait_for_device_node() for the original block device symlinks or the
# original block device nodes that existed on the original system where "rear mkrescue" had been running
# because it is unknown which of those block device symlinks or block device nodes may also appear here
# on the current (replacement) system where "rear recover" is currently running.
# So for now we sleep 2 seconds and call "udevadm settle" before calling block_device_symlinks() and hope for the best
# (in particular "udevadm settle" may silently wait up to its default timeout value of 120 seconds):
LogPrint "Waiting for 'udevadm settle' to let block device nodes and block device symlinks appear that are needed for LVM"
sleep 2
udevadm settle
block_device_symlinks >$RECREATING_BLOCKDEV_SYMLINKS_FILE
for orig_pv_dev in $( grep '^LVM physical volume devices ' $STORAGE_LVM_OUTPUT_FILE | cut -d ' ' -f5- ) ; do
    # Determine what kernel device node to use for creating the LVM physical volume.
    # Because $orig_pv_dev is usually a kernel device node name like /dev/sdb2 or /dev/md123
    # and kernel device node names are not stable, cf. https://github.com/rear/rear/issues/2254
    # we need to find out what kernel device node on the current (replacement) system where "rear recover" is running
    # match $orig_pv_dev that is the kernel device node on the original system where "rear mkrescue" had been running.
    # To do that we get all original block device symlinks that had pointed to $orig_pv_dev on the original system and
    # try to find same current block device symlinks and use a current kernel device node where a symlink points to.
    # If there is a unique current kernel device node where all those symlinks point to we use that device node.
    # Otherwise we try some hopefully reasonable fallback behaviour what current kernel device node to use:
    current_pv_dev=""
    current_targets=()
    # Get all original block device symlinks that had pointed to $orig_pv_dev on the original system:
    orig_pv_dev_symlinks=( $( grep "^$orig_pv_dev " $STORAGE_BLOCKDEV_SYMLINKS_FILE | cut -d ' ' -f2 ) )
    # Try to find same current block device symlinks and get current kernel device nodes where a symlink points to:
    for orig_pv_dev_symlink in "${orig_pv_dev_symlinks[@]}" ; do
        current_targets+=( $( grep " $orig_pv_dev_symlink" $RECREATING_BLOCKDEV_SYMLINKS_FILE | cut -d ' ' -f1 ) )
    done
    # Remove duplicates in the current kernel device nodes where a current symlink points to:
    current_orig_pv_dev_symlinks_targets=( $( for current_target in "${current_targets[@]}" ; do echo $current_target ; done | sort -u ) )
    # Fallback behaviour when no current symlink was found that also had exited on the original system:
    if ! test "${current_orig_pv_dev_symlinks_targets[*]}" ; then
        LogPrint "For LVM PV $orig_pv_dev no matching device symlink found (nothing like ${orig_pv_dev_symlinks[*]})"
        if test -b "$orig_pv_dev" ; then
            LogPrint "Creating LVM PV using its original device $orig_pv_dev as last resort"
            current_pv_dev=$orig_pv_dev
        else
            LogPrintError "Cannot create LVM PV for $orig_pv_dev (no matching kernel block device found)"
            continue
        fi
    fi
    # If there is a unique current kernel device node where all those symlinks point to use that one:
    if test 1 -eq ${#current_orig_pv_dev_symlinks_targets[@]} ; then
        current_pv_dev=${current_orig_pv_dev_symlinks_targets[0]}
        LogPrint "Creating LVM PV for $orig_pv_dev using its current unique matching device $current_pv_dev"
    else
        # Fallback behaviour when things are not unique:
        LogPrint "For LVM PV $orig_pv_dev found device symlinks that point to different targets ${current_orig_pv_dev_symlinks_targets[*]}"
        for current_pv_dev in "${current_orig_pv_dev_symlinks_targets[@]}" ; do
            if test "$current_pv_dev" = "$orig_pv_dev" ; then
                LogPrint "Creating LVM PV by using $current_pv_dev that is same as the original device as best guess"
                break
            fi
        done
        if ! test "$current_pv_dev" = "$orig_pv_dev" ; then
            current_pv_dev=${current_orig_pv_dev_symlinks_targets[0]}
            LogPrint "Creating LVM PV for $orig_pv_dev using $current_pv_dev as fallback (first of the symlinks targets)"
        fi
    fi
    # Final test to be on the safe side:
    if ! test -b "$current_pv_dev" ; then
        LogPrintError "Cannot create LVM PV for $orig_pv_dev (its current matching device '$current_pv_dev' is no block device)"
        continue
    fi
    # Get the UUID:
    pv_uuid="$( grep "^$orig_pv_dev *PV UUID " $STORAGE_LVM_OUTPUT_FILE | tr -s '[:blank:]' ' ' |  cut -d ' ' -f4 )"
    if ! test "$pv_uuid" ; then
        LogPrintError "Cannot create LVM PV for $orig_pv_dev (no matching 'PV UUID' found in $STORAGE_LVM_OUTPUT_FILE)"
        continue
    fi
    # Create the LVM physical volume:
    # Using '-ff' is mandatory because with only a single '-f' it sometimes fails with the message
    #   Can't initialize physical volume "/dev/somePVdev" of volume group "someVG" without -ff
    # but (of course) without a reason why it fails so we play dumb and just do what they ask for:
    if lvm pvcreate $verbose -ff --yes --uuid "$pv_uuid" --norestorefile $current_pv_dev ; then
        # Only for successfully created LVM physical volumes remember their
        # orig_pv_dev current_pv_dev mapping (needed when creating LVM volume groups):
        echo "$orig_pv_dev $current_pv_dev" >>$RECREATING_LVM_PVS_MAPPING_FILE
    else
        LogPrintError "Failed to create LVM PV ('lvm pvcreate -ff --yes --uuid $pv_uuid --norestorefile $current_pv_dev' failed)"
    fi
done

# Creating LVM volume groups:
# Here we need an associative array to avoid awkward coding workarounds.
# The volume_groups associative array elemets have the following form:
#   keyword is the VG name
#   value is a string of PVs that belong to the VG in the keyword
# VG and LV names cannot contain spaces because according to "man lvm"
#   "The valid characters for VG and LV names are: a-z A-Z 0-9 + _ . -"
# PVs are device nodes or symlinks in /dev/ which also do not contain spaces.
# Therefore VG names and PVs are single words so that we can store
# more of them as a string:
local -A volume_groups || Error "Bash associative arrays are required"
local vg_name vg_current_pv_devs
for orig_pv_dev in $( grep '^LVM physical volume devices ' $STORAGE_LVM_OUTPUT_FILE | cut -d ' ' -f5- ) ; do
    vg_name="$( grep "^$orig_pv_dev *VG Name " $STORAGE_LVM_OUTPUT_FILE | tr -s '[:blank:]' ' ' |  cut -d ' ' -f4 )"
    if ! test "$vg_name" ; then
        LogPrintError "Cannot attach LVM PV $orig_pv_dev to a VG (no matching 'VG Name' found in $STORAGE_LVM_OUTPUT_FILE)"
        continue
    fi
    # RECREATING_LVM_PVS_MAPPING_FILE contains "old new" mapping lines of the form "orig_pv_dev current_pv_dev":
    current_pv_dev="$( grep "^$orig_pv_dev " $RECREATING_LVM_PVS_MAPPING_FILE |  cut -d ' ' -f2 )"
    if ! test -b $current_pv_dev ; then
        # It also fails here intentinally when creating the PV for orig_pv_dev had failed above:
        LogPrintError "Cannot attach LVM PV for $orig_pv_dev to VG $vg_name (its current PV '$current_pv_dev' is no block device or empty)"
        continue
    fi
    volume_groups["$vg_name"]+="$current_pv_dev "
done
# Create the LVM volume groups:
for vg_name in "${!volume_groups[@]}" ; do
    vg_current_pv_devs="${volume_groups[$vg_name]}"
    if ! test "$vg_current_pv_devs" ; then
        LogPrintError "Cannot create LVM VG $vg_name (found no current PVs for it)"
        continue
    fi
    # Because under certain circumstances it had happened that 'vgcreate' failed
    # and reported that the VG that is to be creted already exists.
    # So to be more on the safe side we run 'vgremove' before:
    if lvm vgremove $verbose -ff --yes $vg_name ; then
        Log "Unexpectedly 'vgremove' did not fail here because normally $vg_name should not yet exist"
    else
        Log "It is normal that 'vgremove' fails because $vg_name should not yet exist (it is only run as precaution)"
    fi
    # Actually create the VG:
    if lvm vgcreate $verbose -ff --yes $vg_name $vg_current_pv_devs ; then
        LogPrintError "Created LVM VG $vg_name with those PVs: $vg_current_pv_devs"
    else
        LogPrintError "Failed to create LVM VG ('lvm vgcreate -ff --yes $vg_name $vg_current_pv_devs' failed)"
        continue
    fi
done

# Creating LVM logical volumes:

LogPrint "Created LVM physical volumes, LVM volume groups, and LVM logical volumes"


unset -f wait_for_device_node
unset -f kernel_block_device_names

Error "End at ${BASH_SOURCE[0]}"

