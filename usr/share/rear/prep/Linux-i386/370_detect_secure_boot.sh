test "$SECURE_BOOT_BOOTLOADER" && return 0

# Note:
# this is more of a hack than a really good solution.
# The good solution would check the EFI variables for the bootloader
# that is used to boot the system. But this is not implemented yet for
# secure boot.
#
# The code in usr/share/rear/rescue/default/850_save_sysfs_uefi_vars.sh
# could be used as a starting point for this, however currently
# it tries to read the actual boot loader# used only as a last resort
# if well-known files are not found.
#
# try to find a secure boot shim and use it as bootloader, regardless if secure boot
# is enabled or not. This is to support systems that have secure boot disabled but
# still use shim as bootloader. It also enables recovering a system from a non-secure boot
# system to a secure boot system.
SECURE_BOOT_BOOTLOADER=( /boot/efi/EFI/*/shim$EFI_ARCH.efi /boot/efi/EFI/*/shim.efi )
# shellcheck disable=SC2128

local secureboot_status="" mokutil_status="" mokutil_result=0
if type -p mokutil ; then
    PROGS+=( mokutil )
    mokutil_status=$(mokutil --sb-state 2>&1)
    mokutil_result=$?
    if ((mokutil_result == 0)) && grep -q "SecureBoot enabled" <<<"$mokutil_status" ; then
        secureboot_status=true
    else
        secureboot_status=false
    fi
fi

if test "$SECURE_BOOT_BOOTLOADER" ; then
    if is_true "$secureboot_status" ; then
        LogPrint "Secure Boot is active, auto-configuration using '$SECURE_BOOT_BOOTLOADER' as UEFI bootloader"
    else
        LogPrint "Secure boot is disabled, but still using auto-configured '$SECURE_BOOT_BOOTLOADER' as UEFI bootloader"
    fi
else  # no secure boot shim found
    if is_true "$secureboot_status" ; then
        Error "Secure Boot is active, but no shim bootloader found via auto-configuration, you must set SECURE_BOOT_BOOTLOADER to the correct shim bootloader"
    else
        Log "Secure Boot is disabled, no shim bootloader found via auto-configuration"
    fi
fi

return 0
