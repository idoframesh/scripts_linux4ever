#!/bin/bash

# This script makes an ASCII tree out of the directory structure in a
# FLAC music library, by reading tags.

# The script expects this directory structure:
# ${library}/${albumartist}/${album}

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [FLAC library directory]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

# If metaflac isn't installed, quit running the script.
command -v metaflac 1>&- || { printf '\n%s\n\n' 'This script requires metaflac.'; exit; }

declare library artist_dn album_dn if albumartist album year tracks
declare -a dirs1 dirs2
declare -A alltags

library=$(readlink -f "$1")

gettags () {
	declare line field
	declare -a lines

	for field in "${!alltags[@]}"; do
		unset -v alltags["${field}"]
	done

	mapfile -t lines < <(metaflac --no-utf8-convert --export-tags-to=- "$if" 2>&-)

	for (( z = 0; z < ${#lines[@]}; z++ )); do
		line="${lines[${z}]}"

		unset -v mflac
		declare -a mflac

		mflac[0]="${line%%=*}"
		mflac[1]="${line#*=}"

		if [[ -z ${mflac[1]} ]]; then
			continue
		fi

		field="${mflac[0],,}"

		if [[ -n ${alltags[${field}]} ]]; then
			continue
		fi

		alltags["${field}"]="${mflac[1]}"
	done
}

# Enters the Songbird Music Library directory.
cd "$library"

mapfile -t dirs1 < <(find "$library" -mindepth 1 -maxdepth 1 -type d 2>&-)

for (( i = 0; i < ${#dirs1[@]}; i++ )); do
	artist_dn="${dirs1[${i}]}"

	if [[ ! -d $artist_dn ]]; then
		continue
	fi

	if=$(find "$artist_dn" -type f -iname "*.flac" | head -1)

	gettags
	albumartist="${alltags[albumartist]}"

	printf "+---%s\n" "$albumartist"
	printf "|    %s\n" '\'

	mapfile -t dirs2 < <(find "$artist_dn" -mindepth 1 -maxdepth 1 -type d 2>&-)

	for (( j = 0; j < ${#dirs2[@]}; j++ )); do
		album_dn="${dirs2[${j}]}"

		if [[ ! -d $album_dn ]]; then
			continue
		fi

		if=$(find "$album_dn" -type f -iname "*.flac" 2>&- | head -1)

		if [[ -z $if ]]; then
			continue
		fi

		gettags
		album="${alltags[album]}"
		year="${alltags[date]}"
		tracks="${alltags[totaltracks]}"

		if [[ -z $year ]]; then
			year="???"
		fi

		if [[ -z $tracks ]]; then
			tracks="???"
		fi

		printf "|     %s (%s)\n" "$album" "$year"
		printf "|     %s tracks.\n" "$tracks"
		printf "|\n"
	done
done
