# install-workflow.sh
#
# install workflow for Relax-and-Recover
#
# install-workflow.sh is derived from recover-workflow.sh
#
#    Relax-and-Recover is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    Relax-and-Recover is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with Relax-and-Recover; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#

# Do not show the install workflow by "rear help" but show it by "rear -v help":
if test "$VERBOSE" ; then
    WORKFLOW_install_DESCRIPTION="install from scratch (experimental, under development, only for testing, ask <jsmeix@suse.de> for details)"
fi

# Make the install workflow known to "rear help"
# (currently (Dec. 2015) WORKFLOWS (with trailing 'S') is only used in help-workflow.sh):
WORKFLOWS=( ${WORKFLOWS[@]} install )

# The stages of the install workflow are the same as the stages of the recover workflow
# except SourceStage "verify" that verifies tha backup which is not needed for installation
# and except SourceStage "restore" that is replaced with several SourceStage "install/...".
# There is no longer SourceStage "finalize" that installed the boot loader in the recover workflow
# because the boot loader is now configured and installed in SourceStage "install/configure":
function WORKFLOW_install () {
    # First and foremost initialize what is specific for the install workflow:
    SourceStage "install/initialize"
    # The "setup" stage runs only an optional pre recovery script
    # that could be also needed in case of an installation:
    SourceStage "setup"
    # Set up persistent storage (disk partitioning with filesystems and mount points):
    SourceStage "layout/prepare"
    SourceStage "layout/recreate"
    # Prepare for payload dump (software installation) and configuration:
    SourceStage "install/prepare"
    # Dump the payload into the persistent storage (install files).
    # Usually "dump the payload" means to install software packages:
    SourceStage "install/payload"
    # Basic system configuration so that it can boot
    # (i.e. boot loader configuration and creating etc/fstab)
    # and that 'root' can log in (i.e. initial temporary root password,
    # keyboard layout, basic networking like DHCP plus SSH,...):
    SourceStage "install/configure"
    # Clean up after payload dump and configuration:
    SourceStage "install/wrapup"
    # Copy log file into the target system:
    Source "wrapup/default/99_copy_logfile.sh"
}

