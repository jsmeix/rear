
# Set up and initialize what is special for the install workflow:

# disklayout.conf must exist as /var/lib/rear/layout/disklayout.conf
# and not as /etc/rear/disklayout.conf because in the latter case
# layout/prepare/default/01_prepare_files.sh would "entering Migration mode"
# and in "Migration mode" layout/prepare/default/25_compare_disks.sh
# would be "Switching to manual disk layout configuration"
# which is not inteded for the install workflow because here it is assumed
# that disklayout.conf is already exactly as needed for installation
# (i.e. there is no "Migration mode" for installation):
if test -e $CONFIG_DIR/disklayout.conf ; then
    LogPrint "Manual disk layout configuration/migration mode will be used because $CONFIG_DIR/disklayout.conf exists."
fi
if ! test -s $VAR_DIR/layout/disklayout.conf ; then
    Error "Installation will probably fail without a proper $VAR_DIR/layout/disklayout.conf file."
fi

# To finally do something (e.g. umount the target system) it must be done as ExitTask and
# because the exit tasks are executed in reverse ordering of how AddExitTask is called
# (see AddExitTask in _input-output-functions.sh) the ordering of how AddExitTask is called
# must begin with the to-be-last-run exit task and end with the to-be-first-run exit task
# which means the final exit task of a workflow must be added at the beginning of the workflow:
if test "$INSTALL_FINAL_EXIT_TASK" ; then
    Debug "Adding final exit task for the install workflow: '$INSTALL_FINAL_EXIT_TASK'"
    AddExitTask "$INSTALL_FINAL_EXIT_TASK"
fi

