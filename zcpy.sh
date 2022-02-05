#!/bin/bash
read -r -d '' DOCUMENTATION <<END
#
# A simple script to (incrementally) copy ZFS datasets.
#
# This script only supports copying datasets *within a single system*, albeit
# between pools. It cannot copy datasets to a remote machine, for doing so
# use much smarter 'zrep' (which was an inspiration for this script)
#
# The main usecase is to copy datasets from (fast) SSD pool to (slower but larger)
# HDD pool for snapshotting. Usefull when SSD pools space is limited.
#
# The copying is done using 'zfs send' and 'zfs receive'. 'zcpy.sh' keeps last
# copied snapshot on both source and destination datasets to allow incremental
# copies (once the initial full copy is done).
#
# By default, this script runs in 'paranoid' mode and performs various checks
# before actually copies the data and updates destination dataset:
#
# * checks that zcpy:destination on source dataset matches the actual
#   destination on command line.
#
# * checks that zcpy:source on destination dataset matches the actual
#   source on command line.
#
# * checks that destinations dataset is read-only.
#
# If any of the above fails, no data are copied and erorr is printed.
#
# If the destinations dataset does not exist, it is created, made read-only and
# and zcpy:* properties are set accordingly. 
#
# If the destination dataset does exist and '--initial' is passed, then 'zcpy.sh'
# looks for newest source snapshot that also exists on destination and if found,
# data are copied, destination is made read-only and and zcpy:* properties are set
# accordingly. If not such snapshot is found, 'zcpy.sh' gives up asking user to
# resolve the problem manually (by creating such snapshots, for example).
#
# [1]: http://www.bolthole.com/solaris/zrep/
#
END
set -e

function error {
	echo "Error: $1"
	exit 1
}

function info {
	echo "Info: $1"
}

function usage {
	echo "$DOCUMENTATION"
	cat <<END

Usage:
$0 [--initial] [--test|--dry-run] <SOURCE> <TARGET>

--initial	do initial setup and copy, use first time only.
--test
--dry-run	print what it will be done but do not actually
                perform any operations on ZFS datasets.
--help          print this message.
END
	exit 0
}

zfs_eval=eval
initial=no

for arg
do
	shift
	case "$arg" in
		--help)
			usage
			;;
		--initial)
			initial=yes
			;;
		--test|--dry-run)
			zfs_eval=echo
			;;
		--*)
			error "unknown option: $arg"
			;;
		*)
			set -- "$@" "$arg"
			;;
	esac
done

if [ -z $1 ]; then echo "Usage: $0 <SOURCE> <TARGET>"; exit 1; fi
if [ -z $2 ]; then echo "Usage: $0 <SOURCE> <TARGET>"; exit 1; fi

src_fs=$1
dst_fs=$2

if ! zfs list -Ho name "${src_fs}" > /dev/null; then
	error "source dataset does not exist: ${src_fs}"
fi

if ! zfs list -Ho name "${dst_fs}" > /dev/null; then
	dst_fs_exists="no"
	initial="yes"
else
	dst_fs_exists="yes"
fi


src_fs_prop_dst=$(zfs get -Ho value "zcpy:destination" "${src_fs}")
if [ "${dst_fs_exists}" == "yes" ]; then
	dst_fs_prop_src=$(zfs get -Ho value "zcpy:source" "${dst_fs}")
	dst_fs_prop_ro=$(zfs get -Ho value "readonly" "${dst_fs}")
else
	dst_fs_prop_src=-
	dst_fs_prop_ro=off
fi

src_snap_new="${src_fs}@zcpy-$(date +%Y-%m-%d_%H-%M-%S)"

if [ "$zfs_dst_exists" == "no" ]; then
	$zfs_eval zfs snapshot -r "${src_snap_new}"
	$zfs_eval trap "$zfs_eval zfs destroy -r \"${src_snap_new}\"" EXIT
	$zfs_eval zfs create -p $(dirname "${dst_fs}")
	$zfs_eval zfs send -R "${src_snap_new}" \| pv \| zfs recv -u "${dst_fs}"
	trap - EXIT
else
	if [ "$initial" == "yes" ]; then
		# Destination exists, but we're doing the initial setup. First, check whether we are
                # calling --initial second time!
		if [ "$src_fs_prop_dst" != "-" ]; then
			error "zcpy:destination property already set on source dataset, cannot initialize!"
		fi

		if [ "$dst_fs_prop_src" != "-" ]; then
			error "zcpy:source property already set on destination dataset, cannot initialize"
		fi

		# Good, now look for newest source snapshot that also exists in destination. 
		# If none is found, give up.
		for src_snap in $(zfs list -t snap -Ho name -S creation "${src_fs}"); do
			dst_snap="${dst_fs}@${src_snap#*@}"
			if zfs list -t snap "${dst_snap}"; then
				src_snap_old="${src_snap}"
				dst_snap_old="${dst_snap}"
				break
			fi
		done
		if [ -z "${src_snap_old}" -o -z "${dst_snap_old}" ]; then
			error "could not find any common snapshot, please initialize manually"
		fi
	else
		# Destination exists and we're NOT initializing, so perform paranoid checks.
		src_snap_old=$(zfs list -t snapshot -H -o name -s creation "${src_fs}" | grep "@zcpy-" | sort | tail -n1)
		dst_snap_old="${dst_fs}@${src_snap_old#*@}"

		if [ "$src_fs_prop_dst" == "-" ]; then
			error "zcpy:destination property not set on source dataset: ${src_fs}"
		elif [ "$src_fs_prop_dst" != "${dst_fs}" ]; then
			error "zcpy:destination property value does not match: expecting ${dst_fs}, got: ${src_fs_prop_dst}"
		fi

		if [ "$dst_fs_prop_src" == "-" ]; then
			error "zcpy:source property not set on destination dataset: ${dst_fs}"
		elif [ "$dst_fs_prop_src" != "${src_fs}" ]; then
			error "zcpy:source property value does not match: expecting ${src_fs}, got: ${dst_fs_prop_src}"
		fi

		if [ "dst_fs_prop_ro" == "off" ]; then
			error "destination dataset is not read only: ${dst_fs}"
		fi
	fi
	# Now, do an incremental send...
	$zfs_eval zfs snapshot -r "${src_snap_new}"
	trap "$zfs_eval zfs destroy -r \"${src_snap_new}\"" EXIT
	$zfs_eval zfs send -I "${src_snap_old}" "${src_snap_new}" \| pv \| zfs recv -u "${dst_fs}"
	trap - EXIT
	# ...and destroy old snapshots
	if [ "$initial" == "no" ]; then
		$zfs_eval zfs destroy "${src_snap_old}"
		$zfs_eval zfs destroy "${dst_snap_old}"
	fi
fi

if [ "$initial" == "yes" ]; then
	$zfs_eval zfs set "zcpy:destination=${dst_fs}" "${src_fs}"
	$zfs_eval zfs set "zcpy:source=${src_fs}" "${dst_fs}"
	$zfs_eval zfs set "readonly=on" "${dst_fs}"
fi
