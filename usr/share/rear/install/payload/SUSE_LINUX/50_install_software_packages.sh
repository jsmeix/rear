
# Software installation:

if test "$INSTALL_PAYLOAD_SUSE_ZYPPER_BASEPRODUCT_FILE" ; then
    Debug "Avoid the zypper warning that 'The /etc/products.d/baseproduct symlink is dangling or missing'."
    mkdir -p $RECOVERY_FS_ROOT/etc/products.d
    ln -s $INSTALL_PAYLOAD_SUSE_ZYPPER_BASEPRODUCT_FILE $RECOVERY_FS_ROOT/etc/products.d/baseproduct
fi

if test "$INSTALL_PAYLOAD_SUSE_ZYPPER_SOFTWARE_REPOSITORIES" ; then

    Debug "Adding zypper software repositories."
    local zypper_repository_number=0;
    for zypper_software_repository in $INSTALL_PAYLOAD_SUSE_ZYPPER_SOFTWARE_REPOSITORIES ; do
        zypper_repository_number=$(( zypper_repository_number + 1 ))
        zypper -v -R $RECOVERY_FS_ROOT addrepo $zypper_software_repository repository$zypper_repository_number
    done

    Debug "First and foremost installing the very basic stuff (i.e. aaa_base and what it requires),"
    zypper -v -R $RECOVERY_FS_ROOT -n install aaa_base
    # aaa_base requires filesystem so that zypper installs filesystem before aaa_base
    # but for a clean filesystem installation RPM needs users and gropus
    # as shown by RPM as warnings like (excerpt):
    #   warning: user news does not exist - using root
    #   warning: group news does not exist - using root
    #   warning: group dialout does not exist - using root
    #   warning: user uucp does not exist - using root
    # Because those users and gropus are created by aaa_base scriptlets and
    # also RPM installation of permissions pam libutempter0 shadow util-linux
    # (that get also installed before aaa_base by zypper installation of aaa_base)
    # needs users and gropus that are created by aaa_base scriptlets so that
    # those packages are enforced installed a second time after aaa_base was installed:
    for package in filesystem permissions pam libutempter0 shadow util-linux ; do
        zypper -v -R $RECOVERY_FS_ROOT -n install -f $package
    done

    if test "$INSTALL_PAYLOAD_SUSE_ZYPPER_INSTALL_ITEMS" ; then
        Debug "Installing the requested software (i.e. installing '$INSTALL_PAYLOAD_SUSE_ZYPPER_INSTALL_ITEMS')."
        for zypper_install_item in $INSTALL_PAYLOAD_SUSE_ZYPPER_INSTALL_ITEMS ; do
            zypper -v -R $RECOVERY_FS_ROOT -n install $zypper_install_item
        done
    fi

    Debug "Verifying dependencies of installed packages and in case of issues let zypper fix them."
    zypper -v -R $RECOVERY_FS_ROOT -n verify --details

    Debug "Removing the software repositores."
    for i in $( seq $zypper_repository_number ) ; do
        zypper -v -R $RECOVERY_FS_ROOT removerepo 1
    done

    Debug "Reporting the differences of what is in the RPM packages compared to the actually installed files in the target system."
    chroot $RECOVERY_FS_ROOT /bin/bash -c "rpm -Va || true"

fi

