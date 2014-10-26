#!/bin/sh

# Script for updating the host using the build(7) results
# from a buildjail.

# Two modes of operation.

# First mode runs the 'make installkernel' part of the update
# procedure. Also records the installed kernel version with 
# ZFS user properties on the root filesystem.

# TODO: Remove debug prints. Add proper notices where appropriate. 

# TODO: Explore the usefulness of recording of sha256 hash of the
# installed /boot/kernel/kernel into the ZFS user properties.
# A mismatch would mean that 'make installkernel' has been run and
# /boot/kernel/kernel has changed. 

# TODO: Guarantee atomicity of the operation. Either both the kernel
# gets installed successfully and the ZFS property operations are
# finished or the operations get rolled back to the initial state 
# in case of any error. 


# Second mode is run after update of world to record the installed
# world version using another set of ZFS user properties
# on the root filesystem.

# TODO: This could actually do everything in one go. Unless the host
# is running on non-standard securelevel(7) installworld will work fine
# over running system.

# TODO: Snapshot the system before install for possible rollback.


# Include common functions and settings

PREFIX_SHARE="${SYSUPDATEPREFIX}/share"
SHARE_RDNZL="${PREFIX_SHARE}/rdnzl"

. "${SHARE_RDNZL}/zfs-functions.sh"
. "${SHARE_RDNZL}/svn-functions.sh"
. "${PREFIX_SHARE}/rdnzl-sysupdate/sysupdate-common.sh"
. "${SYSUPDATEPREFIX}/etc/rdnzl-sysupdate.rc"

usage()
{
    echo "Usage: $0 buildjail " 
    exit 0
}


: ${BUILDJAIL:="$1"}

# Buildjail is a required argument, there is no reasonable default.
if test -z "${BUILDJAIL}"; then
    usage
fi


# Read the SVN revision from the buildjail

BUILDJAIL_FS="${JAIL_BASEFS}/${BUILDJAIL}"
BUILDJAILSRC_FS="${BUILDJAIL_FS}/src"
BUILDJAILOBJ_FS="${BUILDJAIL_FS}/obj"


if ! rdnzl_zfs_filesystem_exists "${BUILDJAIL_FS}"; then
    echo "No such buildjail filesystem ${BUILDJAIL_FS}"
    exit 1
fi

if ! rdnzl_zfs_filesystem_exists "${BUILDJAILSRC_FS}"; then
    echo "No such buildjail src filesystem ${BUILDJAILSRC_FS}"
    exit 1
fi

if ! rdnzl_zfs_filesystem_exists "${BUILDJAILOBJ_FS}"; then
    echo "No such buildjail obj filesystem ${BUILDJAILOBJ_FS}"
    exit 1
fi



SRC_SVNREVISION=$(rdnzl_zfs_get_property_value "${BUILDJAILSRC_FS}" "${SVNREVISIONPROP}") || \
    { echo "Can not read SVNREVISION from filesystem ${BUILDJAILSRC_FS}"; exit 1;}

SRC_SVNBRANCH=$(rdnzl_zfs_get_property_value "${BUILDJAILSRC_FS}" "${SVNBRANCHPROP}") || \
    { echo "Can not read SVNBRANCH from filesystem ${BUILDJAILSRC_FS}"; exit 1;}

BUILDJAILSRC_MNT=$(rdnzl_zfs_get_property_value "${BUILDJAILSRC_FS}" "mountpoint")

OBJ_SVNREVISION=$(rdnzl_zfs_get_property_value "${BUILDJAILOBJ_FS}" "${SVNREVISIONPROP}") || \
    { echo "Can not read SVNREVISION from filesystem ${BUILDJAILOBJ_FS}"; exit 1;}

OBJ_SVNBRANCH=$(rdnzl_zfs_get_property_value "${BUILDJAILOBJ_FS}" "${SVNBRANCHPROP}") || \
    { echo "Can not read SVNBRANCH from filesystem ${BUILDJAILOBJ_FS}"; exit 1;}

BUILDJAILOBJ_MNT=$(rdnzl_zfs_get_property_value "${BUILDJAILOBJ_FS}" "mountpoint")

# Require that the SVN revisions of sources and objects match

if test "${OBJ_SVNREVISION}" -lt "${SRC_SVNREVISION}"; then
    echo "OBJ_SVNREVISION is lesser than SRC_SVNREVISION."
    echo "Have buildworld and buildkernel been run in the buildjail yet?"
    exit 1
fi



ROOT_DATASET=$(rdnzl_zfs_filesystem_from_path "/")

echo "ROOT_DATASET: ${ROOT_DATASET}"


# Read the SVN revisions of installed kernel and world. If the ZFS user properties
# are not present the revision should be interpreted as 0 (TODO). 

KERNEL_SVNREVISION=$(rdnzl_zfs_get_property_value "${ROOT_DATASET}" "${KERNELSVNREVISIONPROP}")
KERNEL_SVNBRANCH=$(rdnzl_zfs_get_property_value "${ROOT_DATASET}" "${KERNELSVNBRANCHPROP}")
WORLD_SVNREVISION=$(rdnzl_zfs_get_property_value "${ROOT_DATASET}" "${SVNREVISIONPROP}")
WORLD_SVNBRANCH=$(rdnzl_zfs_get_property_value "${ROOT_DATASET}" "${SVNBRANCHPROP}")

echo "KERNEL_SVNREVISION: ${KERNEL_SVNREVISION}"
echo "KERNEL_SVNBRANCH: ${KERNEL_SVNBRANCH}"
echo "WORLD_SVNREVISION: ${WORLD_SVNREVISION}"
echo "WORLD_SVNBRANCH: ${WORLD_SVNBRANCH}"
echo "OBJ_SVNREVISION: ${OBJ_SVNREVISION}"
echo "OBJ_SVNBRANCH: ${OBJ_SVNBRANCH}"


# Mount /usr/src and /usr/obj if needed
if ! /sbin/mount | grep -q 'on /usr/src'; then
    /sbin/mount_nullfs "${BUILDJAILSRC_MNT}" /usr/src
fi   

if ! /sbin/mount | grep -q 'on /usr/obj'; then
    /sbin/mount_nullfs "${BUILDJAILOBJ_MNT}" /usr/obj
fi   

echo "Going to perform 'make installkernel' in /usr/src to install the new kernel."

# TODO: Find a way to revert /boot/kernel* to initial state
# if 'make installkernel' fails midway.

# Run 'make installkernel'
/usr/bin/make -C /usr/src installkernel || \
    { echo "'make installkernel' failed"; exit 1; }

# Record the revision of the newly installed kernel to ZFS user property.
"${ZFS_CMD}" set "${KERNELSVNREVISIONPROP}=${OBJ_SVNREVISION}" "${ROOT_DATASET}"

# Branch as well in case it got changed
"${ZFS_CMD}" set "${KERNELSVNBRANCHPROP}=${OBJ_SVNBRANCH}" "${ROOT_DATASET}"

# Acknowledge that the kernel got installed
    echo "Installed kernel from build that was done with sources of"
    echo "branch ${OBJ_SVNBRANCH} and SVN revision ${OBJ_SVNREVISION}."
    

# Run the installworld sequence
# TODO: Check for errors in each step

/usr/bin/make -C /usr/src installworld

/usr/sbin/mergemaster

/usr/bin/make -C /usr/src -D BATCH_DELETE_OLD_FILES delete-old delete-old-libs

# Record the revision of the newly installed world to ZFS user property.
"${ZFS_CMD}" set "${SVNREVISIONPROP}=${OBJ_SVNREVISION}" "${ROOT_DATASET}"
# And branch
"${ZFS_CMD}" set "${SVNBRANCHPROP}=${OBJ_SVNBRANCH}" "${ROOT_DATASET}"

echo "Installed world from build that was done with branch ${OBJ_SVNBRANCH} and SVN revision ${OBJ_SVNREVISION}"

exit 0
