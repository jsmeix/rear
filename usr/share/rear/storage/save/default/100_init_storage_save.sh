
# storage/save/default/100_init_storage_save.sh
# initializes directories and files where to storage info gets saved.

LogPrint "Saving storage info (disks, partitions, filesystems, mountpoints, ...)"

Debug "Creating directories where to storage info gets saved (when not existing)"
readonly STORAGE_SAVED_DIR="$VAR_DIR/storage/saved"
mkdir -p $v "$STORAGE_SAVED_DIR"

# We need directory for XFS options only if XFS is in use:
if test "$( mount -t xfs )" ; then
    readonly LAYOUT_XFS_OPT_DIR="$STORAGE_SAVED_DIR/xfs_options"
    mkdir -p $v $LAYOUT_XFS_OPT_DIR
fi

# Save 'lsblk' output in human readable form and in computer readable form:
has_binary lsblk || Error "The 'lsblk' command is required for saving storage info"
REQUIRED_PROGS+=( lsblk )
readonly STORAGE_LSBLK_OUTPUT_FILE="$STORAGE_SAVED_DIR/lsblk.output"
Log "Saving 'lsblk' output to $STORAGE_LSBLK_OUTPUT_FILE"
# See lib/layout-functions.sh how DATE is set: DATE=$( date +%Y%m%d%H%M%S )
echo "'lsblk' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_LSBLK_OUTPUT_FILE
# Have the human readable 'lsblk' output as header comment
# so that it is easier to make sense of the values in computer readable form.
# First try the command
#   lsblk -ipo NAME,KNAME,PKNAME,TRAN,TYPE,FSTYPE,SIZE,MOUNTPOINT
# but on older systems (like SLES11) that do not support all that lsblk things
# try the simpler command
#   lsblk -io NAME,KNAME,FSTYPE,SIZE,MOUNTPOINT
# and as fallback try 'lsblk -i' and finally call plain 'lsblk' (and hope for the best):
{ echo "Output of lsblk -ipo NAME,KNAME,PKNAME,TRAN,TYPE,FSTYPE,SIZE,MOUNTPOINT"
  lsblk -ipo NAME,KNAME,PKNAME,TRAN,TYPE,FSTYPE,SIZE,MOUNTPOINT || lsblk -io NAME,KNAME,FSTYPE,SIZE,MOUNTPOINT || lsblk -i || lsblk
  echo "Output of lsblk -bpPO"
} >>$STORAGE_LSBLK_OUTPUT_FILE
# Make all lines up to now as header comments:
sed -i -e 's/^/# /' $STORAGE_LSBLK_OUTPUT_FILE
# Save 'lsblk' output in computer readable form (size as byte values):
lsblk -bpPO >>$STORAGE_LSBLK_OUTPUT_FILE || Error "Required command 'lsblk -bpPO' failed with exit code $?"

# For all 'disk' type kernel device names in the 'lsblk' output
# save the 'parted' output in human readable form and in computer readable form:
has_binary parted || Error "The 'parted' command is required for saving storage info"
REQUIRED_PROGS+=( parted )
readonly STORAGE_PARTED_OUTPUT_FILE="$STORAGE_SAVED_DIR/parted.output"
echo "# 'parted' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_PARTED_OUTPUT_FILE
# Provide the 'parted -m' output format description as comment
# so that it is easier to make sense of the values in computer readable form.
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
 (for CHS/CYL) "number":"begin":"end":"filesystem-type":"partition-name":"flags-set"; ' | sed -e 's/^/#/'
} >>$STORAGE_PARTED_OUTPUT_FILE
# A 'lsblk -bpPO' output line looks like (excerpts):
#   NAME="/dev/sda" KNAME="/dev/sda" ... TYPE="disk" ... PKNAME="" ...
# so we grep for ' KNAME=...' with a leading blank to exclude 'PKNAME' and
# from the result KNAME="/dev/sda" we cut the second field /dev/sda with " field delimiter:
local disk_kname parted_exit_code
for disk_kname in $( grep 'TYPE="disk"' $STORAGE_LSBLK_OUTPUT_FILE | grep -o ' KNAME="[^"]*"' | cut -d '"' -f2 ) ; do
    Log "Saving 'parted' output for $disk_kname to $STORAGE_PARTED_OUTPUT_FILE"
    # Have the human readable 'parted' output (with MiB values and discarded empty lines)
    # so that it is easier to make sense of the values in computer readable form.
    # Using # as sed 's' command delimiter because / is in $disk_kname (e.g. /dev/sda):
    { echo "##### Output of parted -s $disk_kname unit MiB print (with $disk_kname prefix added)"
      parted -s $disk_kname unit MiB print | grep -v '^$' | sed -e "s#^#$disk_kname #"
      echo "### Output of parted -sm $disk_kname unit B print (with $disk_kname prefix added)"
    } >>$STORAGE_PARTED_OUTPUT_FILE
    # Save the 'parted' output in computer readable form (with byte values)
    # with the kernel device name as line prefix added.
    # Using # as sed 's' command delimiter because / is in $disk_kname (e.g. /dev/sda).
    # Using a subshell to run the pipe with 'set -o pipefail' in a separated environment
    # but a drawback of the subshell is that we cannot get "${PIPESTATUS[@]}" out of it
    # so we cannot determine what command in the pipe had failed and therefore
    # we assume 'sed' never fails and report "parted failed" if there was any failure and
    # accordingly we also assume the subshell return code is the exit code from parted:
    ( set -o pipefail
      parted -sm $disk_kname unit B print | sed -e "s#^#$disk_kname #"
    ) >>$STORAGE_PARTED_OUTPUT_FILE
    parted_exit_code=$?
    if test $parted_exit_code -ne 0 ; then
        # Document in STORAGE_PARTED_OUTPUT_FILE that the 'parted' command had failed:
        echo "### Non zero exit code $parted_exit_code from parted -sm $disk_kname unit B print" >>$STORAGE_PARTED_OUTPUT_FILE
        Error "Required command 'parted -sm $disk_kname unit B print' failed with exit code $parted_exit_code"
    fi
done

# Save the 'mdadm' output for MD devices aka Linux Software RAID:
readonly STORAGE_MDADM_OUTPUT_FILE="$STORAGE_SAVED_DIR/mdadm.output"
if has_binary mdadm ; then
    # Regardless whether or not MD devices are actually currently used,
    # when the 'mdadm' command is there we save its output even if it is empty
    # so that it is documented when there is no 'mdadm' output but also
    # if there is no longer 'mdadm' output (e.g. when MD devices had been removed).
    REQUIRED_PROGS+=( mdadm )
    Log "Saving 'mdadm' output to $STORAGE_MDADM_OUTPUT_FILE"
    echo "# 'mdadm' output dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_MDADM_OUTPUT_FILE
    echo "# Output of mdadm --detail --scan" >>$STORAGE_MDADM_OUTPUT_FILE
    mdadm --detail --scan >>$STORAGE_MDADM_OUTPUT_FILE || Error "Required command 'mdadm --detail --scan' failed with exit code $?"
    # A normal 'mdadm --detail --scan' output line looks like:
    #   ARRAY /dev/md/arrayname metadata=1.0 name=hostname:arrayname UUID=43f60cda:d221604f:5d3438a3:8c225f70
    # so we grep for '^ARRAY ' to avoid possible unwanted lines and
    # from the result we cut the second field /dev/md/arrayname with ' ' field delimiter:
    local md_device mdadm_exit_code
    for md_device in $( grep '^ARRAY ' $STORAGE_MDADM_OUTPUT_FILE | cut -d ' ' -f2 ) ; do
        echo "### Output of mdadm --detail $md_device (with $md_device prefix added)" >>$STORAGE_MDADM_OUTPUT_FILE
        # For each ARRAY MD device in STORAGE_MDADM_OUTPUT_FILE save the details
        # with the ARRAY MD device name as line prefix added (and discarded empty lines).
        # Using # as sed 's' command delimiter because / is in $md_device (like /dev/md/arrayname).
        # Using a subshell to run the pipe with 'set -o pipefail' in a separated environment
        # but a drawback of the subshell is that we cannot get "${PIPESTATUS[@]}" out of it
        # so we cannot determine what command in the pipe had failed and therefore
        # we assume 'grep' and 'sed' never fail and report "mdadm failed" if there was any failure
        # and accordingly we also assume the subshell return code is the exit code from mdadm:
        ( set -o pipefail
          mdadm --detail $md_device | grep -v '^$' | sed -e "s#^#$md_device #"
        ) >>$STORAGE_MDADM_OUTPUT_FILE
        mdadm_exit_code=$?
        if test $mdadm_exit_code -ne 0 ; then
            # Document in STORAGE_MDADM_OUTPUT_FILE that the 'mdadm' command had failed:
            echo "### Non zero exit code $mdadm_exit_code from mdadm --detail $md_device" >>$STORAGE_MDADM_OUTPUT_FILE
            Error "Required command 'mdadm --detail $md_device' failed with exit code $mdadm_exit_code"
        fi
    done
else
    # When there are 'raid[0-9]*' TYPE entries in the 'lsblk' output
    # there are MD devices so it is an error when there is no 'mdadm' command:
    grep -q 'TYPE="raid[^"]*"' $STORAGE_LSBLK_OUTPUT_FILE && Error "The 'mdadm' command is required for saving storage info"
    # Document that there is no 'mdadm' command (also to overwrite possibly outdated STORAGE_MDADM_OUTPUT_FILE content):
    echo "# No 'mdadm' output because there is no 'mdadm' command dated $DATE (YYYYmmddHHMMSS)" >$STORAGE_MDADM_OUTPUT_FILE
fi


Error "End at ${BASH_SOURCE[0]}"

