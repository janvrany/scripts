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
# If the destinations dataset does not exist, it is created, made read-only and
# and zcpy:* properties are set accordingly.
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
$0 [--paranoid|--i-know-what-i-m-doing|--help] <SOURCE> <TARGET>

--paranoid               do perform paranoid checks (default)
--i-know-what-i-m-doing  do not perform paranoid checks
--help                   this message.
END
	exit 0
}

paranoid=yes

for arg
do
	shift
	case "$arg" in
		--help)
			usage
			;;
		--parainod)
			;;
		--i-know-what-i-m-doing)
			paranoid=no
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

if ! $(zfs list -Ho name "${src_fs}" > /dev/null); then
	error "source dataset does not exist: ${src_fs}"
fi

if ! $(zfs list -Ho name "${dst_fs}" > /dev/null); then
	dst_fs_exists="no"
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


src_snap_old=$(zfs list -t snapshot -H -o name "${src_fs}" | grep "@zcpy-" | sort | tail -n1)
dst_snap_old="${dst_fs}@${src_snap_old#*@}"

src_snap_new="${src_fs}@zcpy-$(date +%Y-%m-%d_%H-%M-%S)"

if [ -z "{src_snap_old}" ]; then
	info "no snapshot from previous run, doing full copy"
	incremental=no
else
	if [ "${dst_fs_exists}" == "no" ]; then
		info "destination dataset does not exist, creating and doing full copy"
		incremental=no
	elif ! $(zfs list -Ho name "${dst_snap_old}" > /dev/null); then
		info "found snapshot from previous run, but not present in destination, doing full copy"
		incremental=no
	else
		info "found snapshot from previous run, will do incremental copy"
		incremental=yes
	fi
fi

if [ "$paranoid" == "yes" -a "$dst_fs_exists" == "yes" ]; then
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

zfs snapshot -r "${src_snap_new}"

if [ "${incremental}" == "yes" ]; then
	zfs send -R -I "${src_snap_old}" "${src_snap_new}" | pv | zfs recv -u "${dst_fs}"
	zfs destroy -r "${src_snap_old}"
	zfs destroy -r "${dst_snap_old}"
else
	if [ "$dst_fs_exists" == "no" ]; then
		zfs create -p $(dirname "${dst_fs}")
	fi
	zfs send -R "${src_snap_new}" | pv | zfs recv -u "${dst_fs}"
	if [ "$dst_fs_exists" == "no" -o "$paranoid" == "no" ]; then
		zfs set "zcpy:destination=${dst_fs}" "${src_fs}"
		zfs set "zcpy:source=${src_fs}" "${dst_fs}"
		zfs set "readonly=on" "${dst_fs}"
	fi
	if ! [ -z "${src_snap_old}" ]; then
		zfs destroy -r "${src_snap_old}"
	fi
fi
