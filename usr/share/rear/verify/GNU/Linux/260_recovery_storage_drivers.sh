# Find the storage drivers for the recovery hardware.

# When storage drivers seem to have changed for the recovery hardware
# the initrd/initramfs should be recreated by a 'rebuild_initramfs' script.
# Therefore we set here a variable that explicitly requests this.
# REBUILD_INITRAMFS is used like NOBOOTLOADER but the logical meaning is opposite:
# If REBUILD_INITRAMFS has a 'true' value, the initrd/initramfs must be recreated.
# If REBUILD_INITRAMFS has a 'false' value, the initrd/initramfs must not be recreated.
# If REBUILD_INITRAMFS is neither 'true' nor 'false', the initrd/initramfs may or may not be recreated.
# If the user has already set REBUILD_INITRAMFS to a 'true' value, this script is not needed:
if is_true "$REBUILD_INITRAMFS" ; then
    LogPrint "Will do driver migration because REBUILD_INITRAMFS is 'true'"
    return 0
fi
# If the user has already set REBUILD_INITRAMFS to a 'false' value, respect this:
if is_false "$REBUILD_INITRAMFS" ; then
    LogPrint "No driver migration because REBUILD_INITRAMFS is 'false'"
    return 0
fi

# A longer time ago udev was optional on some distros.
# This changed and nowadays udev is not optional any more.
# See https://github.com/rear/rear/pull/1171#issuecomment-274442700
# But it is not necessarily an error if the storage drivers
# for the recovery hardware cannot be determined:
if ! have_udev ; then
    LogPrint "Cannot determine storage drivers (no udev found), proceeding bona fide"
    return 0
fi

FindStorageDrivers $TMP_DIR/dev >$TMP_DIR/storage_drivers

if ! test -s $TMP_DIR/storage_drivers ; then
    Log "No driver migration: No needed storage drivers found ('$TMP_DIR/storage_drivers' is empty)"
    return 0
fi
# During "rear mkbackup/mkrescue" 260_storage_drivers.sh creates $VAR_DIR/recovery/storage_drivers
if cmp -s $TMP_DIR/storage_drivers $VAR_DIR/recovery/storage_drivers ; then
    Log "No driver migration: '$TMP_DIR/storage_drivers' and '$VAR_DIR/recovery/storage_drivers' are the same"
    return 0
fi

# The storage drivers seem to have changed for the recovery hardware
# so that the initrd/initramfs should be recreated by a 'rebuild_initramfs' script:
REBUILD_INITRAMFS="yes"
LogPrint "Will do driver migration plus recreating initrd/initramfs (storage drivers seem to have changed)"

