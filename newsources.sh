#!/bin/sh --

# Script for automatically mounting a new set of sources in a build jail.
# This is run after using svn/svnlite to update the sources.

# Creates a snapshot of the sources and a ZFS clone using the
# snapshot and mounts the clone on the desired jail under the jail
# /usr/src -directory.

# After running this script 'make buildworld buildkernel'
# followed by the usual update procedure should be run on the
# host. The script update-host automates this procedure as much
# as possible. 
  
# After the host has been updated with new kernel and world using
# the update-host.sh script the build jail should be updated by
# running the update-buildjail.sh script.

# TODO: Now this all assumes a simple model where a build is just
# identified by the branch and revision of the sources used.
# A better model would use of named builds that would also contain
# information about the intended use of the build, the set of options
# used (src.conf for example) and whether the build is done with
# modified or pristine sources.

# TODO: Require root privileges, none of this will work as a normal user.
# Same goes for other scripts.

PREFIX_SHARE="${SYSUPDATEPREFIX}/share"
SHARE_RDNZL="${PREFIX_SHARE}/rdnzl"

. "${SHARE_RDNZL}/zfs-functions.sh"
. "${SHARE_RDNZL}/svn-functions.sh"
. "${PREFIX_SHARE}/rdnzl-sysupdate/sysupdate-common.sh"
. "${SYSUPDATEPREFIX}/etc/rdnzl-sysupdate.rc"


usage()
{
    echo "Usage: $0 buildjail" 
    exit 1
}


: ${BUILDJAIL:="$1"}

# Buildjail is a required argument, there is no reasonable default.
if test -z "${BUILDJAIL}"; then
    usage
fi

# Build jail filesystem
BUILDJAIL_FS="${JAIL_BASEFS}/${BUILDJAIL}"


# Sanity checks
if ! rdnzl_zfs_filesystem_exists "${BUILDJAIL_FS}"; then
    echo "No such buildjail filesystem ${BUILDJAIL_FS}"
    exit 1
fi


JAIL_SVNREVISION=$(rdnzl_zfs_get_property_value "${BUILDJAIL_FS}" "${SVNREVISIONPROP}")

# Default to 0 if not known
if test "${JAIL_SVNREVISION}" = "-"; then
    JAIL_SVNREVISION="0"
fi

# This one on the other hand can not be empty,
# we have to know this property to do anything.
JAIL_SVNBRANCH=$(rdnzl_zfs_get_property_value "${BUILDJAIL_FS}" "${SVNBRANCHPROP}") || \
    { echo "Can not read SVNBRANCH from filesystem ${BUILDJAIL_FS}"; exit 1;}

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

SRC_SNAPSHOT="${SRC_FS}@${SRC_SVNREVISION}"



# Dataset for the cloned src tree, created under ${BUILDJAILFS}.
# Branch and SVN revision information stored in ZFS user properties
BUILDJAILSRC_FS="${BUILDJAIL_FS}/src"

# Dataset for /usr/obj in the buildjail
BUILDJAILOBJ_FS="${BUILDJAIL_FS}/obj"

# Construct the mountpoint for BUILDJAILSRC_FS
BUILDJAIL_MNT=$(rdnzl_zfs_get_property_value "${BUILDJAIL_FS}" "mountpoint")

BUILDJAILSRC_MNT="${BUILDJAIL_MNT}/usr/src"

# Same for BUILDJAILOBJ_FS
BUILDJAILOBJ_MNT="${BUILDJAIL_MNT}/usr/obj"


# Bit of debug output...

echo "JAIL_SVNBRANCH: ${JAIL_SVNBRANCH}"

echo "JAIL_SVNREVISION: ${JAIL_SVNREVISION}"

echo "SRC_SVNBRANCH: ${SRC_SVNBRANCH}"

echo "SRC_SVNREVISION: ${SRC_SVNREVISION}"

echo "SRC_SNAPSHOT: ${SRC_SNAPSHOT}"

echo "BUILDJAIL_FS: ${BUILDJAIL_FS}"

echo "BUILDJAILSRC_FS: ${BUILDJAILSRC_FS}"


# Create a snapshot of the source code dataset.
# The snapshot name is the SVN revision of the matching sources
if rdnzl_zfs_snapshot_exists "${SRC_SNAPSHOT}"; then
    echo "Notice: Snapshot ${SRC_SNAPSHOT} already exists, not creating it again."
else
    # TODO: Handle errors
    echo "Creating snapshot ${SRC_SNAPSHOT}"
    "${ZFS_CMD}" snapshot "${SRC_SNAPSHOT}"
fi


# TODO: Check that BUILDJAILSRC_MNT is not a target for another
# mount, for example a nullfs mount to the host /usr/src.
# On that note, /usr/src and /usr/obj that are used to update the host
# could be clones as well so that their contents can be controlled.
# This would mean snapshotting and cloning of the jail /usr/obj
# dataset as well.

# Test if ${BUILDJAILSRC_FS} already exists.
# The -r flag for destroy is for the case there are snapshots on the dataset
# for whatever reason.
if rdnzl_zfs_filesystem_exists "${BUILDJAILSRC_FS}"; then
    echo "Notice: A clone of the system sources already exists at ${BUILDJAILSRC_FS}."
    echo "Destroying ${BUILDJAILSRC_FS}."
    # TODO: Handle errors
    "${ZFS_CMD}" destroy -r "${BUILDJAILSRC_FS}"    
fi


# Create the clone src dataset from the system sources snapshot. 
echo "Creating a new clone of the system sources from snapshot ${SRC_SNAPSHOT} at ${BUILDJAILSRC_FS}."
echo "SVNREVISION: ${SRC_SVNREVISION}"
echo "SVNBRANCH: ${SRC_SVNBRANCH}"
echo "Mountpoint: ${BUILDJAILSRC_MNT}"

# TODO: Handle errors
"${ZFS_CMD}" clone -o mountpoint="${BUILDJAILSRC_MNT}" \
    -o readonly=on -o atime=off \
    -o "${SVNREVISIONPROP}"="${SRC_SVNREVISION}" \
    "${SRC_SNAPSHOT}" "${BUILDJAILSRC_FS}"



# Destroy the jail /usr/obj dataset if it (very likely) exists.
# This will reset the build number to #0 every time the sources
# are updated. The -r flag for destroy for the same reason as above.

# TODO: This will fail if the jail /usr/obj is in use by another
# mount, for example nullfs mount to host /usr/obj.

if rdnzl_zfs_filesystem_exists "${BUILDJAILOBJ_FS}"; then
    echo "Dataset for the jail /usr/obj already exists."
    echo "Destroying ${BUILDJAILOBJ_FS}"
    "${ZFS_CMD}" destroy -r "${BUILDJAILOBJ_FS}"
fi

# Create a new filesystem for the jail /usr/obj directory.
# Don't set the user properties yet since the FS is still empty
# TODO: Handle errors
# TODO: The properties actually get inherited from BUILDJAIL_FS. Try
# finding a way to avoid this (if it causes problems).
echo "Creating a new dataset for ${BUILDJAILOBJ_MNT} at ${BUILDJAILOBJ_FS}."
"${ZFS_CMD}" create -o mountpoint="${BUILDJAILOBJ_MNT}" \
    -o atime=off "${BUILDJAILOBJ_FS}"

# TODO: Force mountd to reload its view of the exported filesystems in case
# the src and obj datasets are exported. Investigate if use of ZFS sharenfs
# property would work better. It could be tested for and 'zfs share/unshare'
# could automate the exporting/unexporting.
