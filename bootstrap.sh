#!/bin/sh

# TODO: Create a driver program that does the common mundane
# tasks like reading in the configuration and includes and then
# passes control to the script that handles the real request.
# For example: 'rdnzl-sysupdate new-sources buildreleng101amd64'
# Would call $PREFIX/share/rdnzl/new-sources.sh with the environment
# set and with argument buildreleng101amd64.

# Script for bootstrapping a buildjail

# Creates a ZFS filesystem for the jail. Optionally downloads and installs a
# distribution set from ftp.freebsd.org into the new jail. Does the
# initial set up of the jail so it is ready to be started.

# Sets up the SVNREVISION and SVNBRANCH properties for the jail filesystem.

# Does not set up /etc/jail.conf entry for the jail but can output usable
# skeleton entry for it.


SHARE_RDNZL="${SYSUPDATEPREFIX}/share/rdnzl-sysupdate"

. "${SHARE_RDNZL}/include/zfs-functions.sh"
. "${SHARE_RDNZL}/include/svn-functions.sh"
. "${SHARE_RDNZL}/include/sysupdate-common.sh"
. "${SYSUPDATEPREFIX}/etc/rdnzl-sysupdate.rc"

usage()
{
    echo "$0 [-h] -a arch -B buildjail -b svnbranch" 
    exit 0
}


# Some useful settings

# Default mirror site. Use HTTP for easier access
FREEBSD_FTP_MIRROR="http://ftp2.freebsd.org/pub/FreeBSD"




# Parse command line arguments.

while getopts "a:B:b:h" o
do
    case "$o" in
    a)  JAIL_ARCH="$OPTARG";;
    B)  BUILDJAIL="$OPTARG";;
    b)  JAIL_SVNBRANCH="$OPTARG";;
    h)  usage;;
    *)  usage;;
    esac
done

shift $((OPTIND-1))

if test -z "${JAIL_ARCH}" || test -z "${BUILDJAIL}" || \
    test -z "${JAIL_SVNBRANCH}"; then
    usage
fi


# For simplicity require that sources for JAIL_SVNBRANCH have already been
# set up. 
# TODO: This script could do that part as well or write another script for
# that task.

# Build jail filesystem
BUILDJAIL_FS="${JAIL_BASEFS}/${BUILDJAIL}"


# Force the selection of sources with JAIL_SVNBRANCH
SRC_FS="${SRC_BASEFS}/${JAIL_SVNBRANCH}"

SRC_MNT=$(rdnzl_zfs_get_property_value "${SRC_FS}" "mountpoint") || \
    { echo "No sources exist for ${BRANCH}/${BRANCHVERSION}"; exit 1;}

echo "SRC_MNT: ${SRC_MNT}"

 
# SVN revision of the source tree
SRC_SVNREVISION=$(rdnzl_svn_get_revision "${SRC_MNT}") || \
    { echo "Can't get SVN revision for ${SRC_MNT}"; exit 1;}

# SVN branch of the source tree
SRC_SVNBRANCH=$(rdnzl_svn_get_branch "${SRC_MNT}") || \
    { echo "Can't get SVN branch for ${SRC_MNT}"; exit 1;}


# The ftp mirror has two subtrees, snapshots for stable etc. and releases for
# the release (releng) versions of FreeBSD. If SRC_SVNBRANCH is releng/* we use
# the releases subtree, otherwise the snapshots subtree.
