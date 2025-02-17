#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified to either upper or lower case.

# The use case for this may be for example to change MS-DOS file names
# (for programs and games) to whatever format you prefer, upper case or
# lower case. I'm a *nix user, so I prefer lower case. Since MS-DOS is
# case insensitive it doesn't matter which format you use, as it will
# show up as upper case from within DOS anyway.

set -eo pipefail

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir] [upper|lower]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
elif [[ $2 != 'upper' && $2 != 'lower' ]]; then
	usage
fi

dir=$(readlink -f "$1")
case="$2"
depth='0'

pause_msg="
You're about to recursively change all the file / directory names
under \"${dir}\" to ${case} case.

Are you sure? [y/n]: "

read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

printf '\n'

mapfile -d'/' -t path_parts <<<"$dir"
depth_orig=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "$dir" -iname "*" 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	f="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"$f"
	depth_tmp=$(( ${#path_parts[@]} - 1 ))
	depth_diff=$(( depth_tmp - depth_orig ))

	if [[ $depth_diff -gt $depth ]]; then
		depth="$depth_diff"
	fi
done

unset -v files path_parts

for (( i = depth; i > 0; i-- )); do
	find "$dir" -mindepth "$i" -maxdepth "$i" -iname "*" | while read f; do
		dn=$(dirname "$f")
		bn=$(basename "$f")

		if [[ $case == 'upper' ]]; then
			new_bn="${bn^^}"
		elif [[ $case == 'lower' ]]; then
			new_bn="${bn,,}"
		fi

		new_f="${dn}/${new_bn}"

		if [[ $new_bn != $bn ]]; then
			printf '%s\n' "$new_f"
			mv -n "$f" "$new_f"
		fi
	done
done
