#
# Copy the logfile and related files to the recovered/installed system,
# at least the part of the logfile that has been written till now.
#

# The following code is only meant to be used for those workflows that install a system:
if test "recover" = "$WORKFLOW" -o "install" = "$WORKFLOW" ; then
    local recover_log_dir=$LOG_DIR/$WORKFLOW
    local target_system_recover_log_dir=$RECOVERY_FS_ROOT/$recover_log_dir
    # Create the directory with mode 0700 (rwx------) so that only root can access files and subdirectories therein
    # because in particular logfiles could contain security relevant information.
    # It is no real error when the following tasks fail so that they return 'true' in any case:
    local copy_log_file_exit_task="mkdir -p -m 0700 $target_system_recover_log_dir && cp -p $LOGFILE $target_system_recover_log_dir || true"
    local copy_layout_files_exit_task="mkdir $target_system_recover_log_dir/layout && cp -pr $VAR_DIR/layout/* $target_system_recover_log_dir/layout || true"
    if test "recover" = "$WORKFLOW" ; then
        local copy_recovery_files_exit_task="mkdir $target_system_recover_log_dir/recovery && cp -pr $VAR_DIR/recovery/* $target_system_recover_log_dir/recovery || true"
        # See below regarding the ordering how exit tasks are executed:
        AddExitTask "$copy_recovery_files_exit_task"
    fi
    # To be backward compatible with whereto the logfile was copied before
    # have it as a symbolic link that points to where the logfile actually is:
    # ( "roots" in roots_home_dir means root's but ' in a variable name is not so good ;-)
    local roots_home_dir=$RECOVERY_FS_ROOT/root
    test -d $roots_home_dir || mkdir $verbose -m 0700 $roots_home_dir >&2
    ln -s $recover_log_dir/$( basename $LOGFILE ) $roots_home_dir/rear-$( date -Iseconds ).log || true
    # Because the exit tasks are executed in reverse ordering of how AddExitTask is called
    # (see AddExitTask in _input-output-functions.sh) the ordering of how AddExitTask is called
    # must begin with the to-be-last-run exit task and end with the to-be-first-run exit task:
    AddExitTask "$copy_layout_files_exit_task"
    AddExitTask "$copy_log_file_exit_task"
fi

