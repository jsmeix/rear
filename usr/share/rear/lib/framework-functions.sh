# shell-script-functions.sh
#
# shell script functions for Relax-and-Recover
#
# This file is part of Relax and Recover, licensed under the GNU General
# Public License. Refer to the included LICENSE for full text of license.
#
# convert tabs into 4 spaces with: expand --tabs=4 file >new-file

# source a file given in $1
function Source () {
    local source_file="$1"
    # An optional error_behaviour="$2" specifies what to do in case of errors, see https://github.com/rear/rear/issues/741
    # Currently the following values for error_behaviour are supported:
    # skip_if_missing : skip sourcing source_file and return successfully if source_file is missing, not found, a directory, or empty
    # exit_if_missing : bail out with BugError if source_file is missing, not found, a directory, or empty
    # If error_behaviour is not specified the default (fully backward compatible) behaviour is:
    # skip sourcing source_file and return successfully if source_file is missing, not found, or empty
    # bail out with Error if source_file is a directory
    local error_behaviour="$2"
    # Test if source file name is empty:
    if test -z "$source_file" ; then
        case "$error_behaviour" in
            (exit_if_missing)
                BugError "Source() was called with empty source file name"
                ;;
            (*)
                Debug "Skipping Source() because it was called with empty source file name"
                return
                ;;
        esac
    fi
    # Use "$SHARE_DIR/$source_file" if "$source_file" is not an absolute path (i.e. when it has no leading '/')
    # see https://github.com/rear/rear/pull/738 and https://github.com/rear/rear/issues/741
    [[ "$source_file" == /* ]] || source_file="$SHARE_DIR/$source_file"
    # Test if source file is a directory:
    if test -d "$source_file" ; then
        case "$error_behaviour" in
            (skip_if_missing)
                Debug "Skipping Source() because source file '$source_file' is a directory"
                return
                ;;
            (exit_if_missing)
                BugError "Source() was called with source file '$source_file' that is a directory"
                ;;
            (*)
                Error "Source file '$source_file' is a directory, cannot source"
                ;;
        esac
    fi
    # Test if source file does not exist of if its content is empty:
    if ! test -s "$source_file" ; then
        case "$error_behaviour" in
            (exit_if_missing)
                BugError "Source() was called with source file '$source_file' not found or empty"
                ;;
            (*)
                Debug "Skipping Source() because source file '$source_file' not found or empty"
                return
                ;;
        esac
    fi
    # Clip leading standard path to rear files (usually /usr/share/rear/):
    local relname="${source_file##$SHARE_DIR/}"
    # Simulate sourcing the scripts in $SHARE_DIR
    if test "$SIMULATE" && expr "$source_file" : "$SHARE_DIR" >&8; then
        LogPrint "Source $relname"
        return
    fi
    # Step-by-step mode or breakpoint if needed
    # Usage of the external variable BREAKPOINT: sudo BREAKPOINT="*foo*" rear mkrescue
    # an empty default value is set to avoid 'set -eu' error exit if BREAKPOINT is unset:
    : ${BREAKPOINT:=}
    [[ "$STEPBYSTEP" || ( "$BREAKPOINT" && "$relname" == "$BREAKPOINT" ) ]] && read -p "Press ENTER to include '$source_file' ..." 2>&1
    Log "Including $relname"
    # DEBUGSCRIPTS mode settings:
    if test "$DEBUGSCRIPTS" ; then
        Debug "Entering debugscripts mode via 'set -$DEBUGSCRIPTS_ARGUMENT'."
        local saved_bash_flags_and_options_commands="$( get_bash_flags_and_options_commands )"
        set -$DEBUGSCRIPTS_ARGUMENT
    fi
    # The actual work (source the source file):
    source "$source_file"
    # Undo DEBUGSCRIPTS mode settings:
    if test "$DEBUGSCRIPTS" ; then
        Debug "Leaving debugscripts mode (back to previous bash flags and options settings)."
        apply_bash_flags_and_options_commands "$saved_bash_flags_and_options_commands"
    fi
    # Breakpoint if needed:
    [[ "$BREAKPOINT" && "$relname" == "$BREAKPOINT" ]] && read -p "Press ENTER to continue ..." 2>&1
}

# collect scripts given in $1 in the standard subdirectories and
# sort them by their script file name and
# source them
function SourceStage () {
    stage="$1"
    shift
    STARTSTAGE=$SECONDS
    Log "Running '$stage' stage"
    scripts=(
        $(
        cd $SHARE_DIR/$stage ;
        # We always source scripts in the same subdirectory structure. The {..,..,..} way of writing
        # it is just a shell shortcut that expands as intended.
        ls -d   {default,"$ARCH","$OS","$OS_MASTER_VENDOR","$OS_MASTER_VENDOR_ARCH","$OS_MASTER_VENDOR_VERSION","$OS_VENDOR","$OS_VENDOR_ARCH","$OS_VENDOR_VERSION"}/*.sh \
            "$BACKUP"/{default,"$ARCH","$OS","$OS_MASTER_VENDOR","$OS_MASTER_VENDOR_ARCH","$OS_MASTER_VENDOR_VERSION","$OS_VENDOR","$OS_VENDOR_ARCH","$OS_VENDOR_VERSION"}/*.sh \
            "$OUTPUT"/{default,"$ARCH","$OS","$OS_MASTER_VENDOR","$OS_MASTER_VENDOR_ARCH","$OS_MASTER_VENDOR_VERSION","$OS_VENDOR","$OS_VENDOR_ARCH","$OS_VENDOR_VERSION"}/*.sh \
            "$OUTPUT"/"$BACKUP"/{default,"$ARCH","$OS","$OS_MASTER_VENDOR","$OS_MASTER_VENDOR_ARCH","$OS_MASTER_VENDOR_VERSION","$OS_VENDOR","$OS_VENDOR_ARCH","$OS_VENDOR_VERSION"}/*.sh \
        | sed -e 's#/\([0-9][0-9]\)_#/!\1!_#g' | sort -t \! -k 2 | tr -d \!
        )
        # This sed hack is neccessary to sort the scripts by their 2-digit number INSIDE indepentand of the
        # directory depth of the script. Basicall sed inserts a ! before and after the number which makes the
        # number always field nr. 2 when dividing lines into fields by !. The following tr removes the ! to
        # restore the original script name. But now the scripts are already in the correct order.
        )
    # if no script is found, then $scripts contains only .
    # remove the . in this case
    test "$scripts" = . && scripts=()

    if test "${#scripts[@]}" -gt 0 ; then
        for script in ${scripts[@]} ; do
            Source $SHARE_DIR/$stage/"$script"
        done
        Log "Finished running '$stage' stage in $((SECONDS-STARTSTAGE)) seconds"
    else
        Log "Finished running empty '$stage' stage"
    fi
}


function cleanup_build_area_and_end_program () {
    # Cleanup build area
    Log "Finished in $((SECONDS-STARTTIME)) seconds"
    if test "$KEEP_BUILD_DIR" ; then
        LogPrint "You should also rm -Rf $BUILD_DIR"
    else
        Log "Removing build area $BUILD_DIR"
        rm -Rf $TMP_DIR
        rm -Rf $ROOTFS_DIR
        # line below put in comment due to issue #465
        #rm -Rf $BUILD_DIR/outputfs
        # in worst case it could not umount; so before remove the BUILD_DIR check if above outputfs is gone
        mount | grep -q "$BUILD_DIR/outputfs"
        if [[ $? -eq 0 ]]; then
            # still mounted it seems
            LogPrint "Directory $BUILD_DIR/outputfs still mounted - trying lazy umount"
            sleep 2
            umount -f -l $BUILD_DIR/outputfs >&2
            rmdir $v $BUILD_DIR/outputfs >&2
        else
            # not mounted so we can safely delete $BUILD_DIR/outputfs
            rm -Rf $BUILD_DIR/outputfs
        fi
        rmdir $v $BUILD_DIR >&2
    fi
    Log "End of program reached"
}

