#!/bin/bash

# This script slowly and gradually lowers the volume until it's equal to
# 0%. Although, any target volume can be set using the $target_volume
# variable. The script takes 1 hour (360 * 10 seconds) all in all, to
# completely lower the volume to the target volume.

# I'm using this script to automatically lower the volume when I fall
# asleep to watching a movie or YouTube.

# https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Migrate-PulseAudio

cfg_fn="${HOME}/lower_volume_pw.cfg"

regex_id='^id ([0-9]+),'
regex_node='^node\.description = \"(.*)\"'
regex_class='^media\.class = \"(.*)\"'
regex_sink='^Audio/Sink$'
regex_volume='^\"channelVolumes\": \[ ([0-9]+\.[0-9]+), [0-9]+\.[0-9]+ \],'
regex_zero='^0+([0-9]+)$'
regex_split='^([0-9]+)([0-9]{6})$'
full_volume=1000000
no_volume=0
target_volume=0
interval=10

declare pw_id

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

# If a SIGINT signal is captured, then put the volume back to where it
# was before running this script.
ctrl_c () {
	if [[ -n $pw_id ]]; then
		set_volume "$volume_og" 'false'
	fi

	printf '%s\n' '** Trapped CTRL-C'

	exit
}

# Creates a function called 'get_id', which decides the audio output to
# use, based on user selection or the existence of a configuration file.
get_id () {
	declare -A pw_parsed nodes

	regex_cfg_node='^node = (.*)$'

	match_node () {
		for pw_id_tmp in "${!nodes[@]}"; do
			pw_node_tmp="${nodes[${pw_id_tmp}]}"

			if [[ $pw_node_tmp == "$pw_node" ]]; then
				pw_id="$pw_id_tmp"

				break
			fi
		done
	}

	declare n

	mapfile -t pw_info < <(pw-cli ls Node | sed -E -e 's/^[[:blank:]]*//' -e 's/[[:space:]]+/ /g')

# Parse the output from 'pw-cli'...
	for (( i = 0; i < ${#pw_info[@]}; i++ )); do
		line="${pw_info[${i}]}"
		
		if [[ $line =~ $regex_id ]]; then
			if [[ -z $n ]]; then
				n=0
			else
				n=$(( n + 1 ))
			fi

			pw_parsed["${n},id"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ $regex_node ]]; then
			pw_parsed["${n},node"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ $regex_class ]]; then
			pw_parsed["${n},class"]="${BASH_REMATCH[1]}"
		fi
	done

# Save the ids and node names of every node that's an audio sink.
	for (( i = 0; i < n; i++ )); do
		if [[ ${pw_parsed[${i},class]} =~ $regex_sink ]]; then
			nodes["${pw_parsed[${i},id]}"]="${pw_parsed[${i},node]}"
		fi
	done

	unset -v n

# If the configuration file exists, get the node name from that.
	if [[ -f $cfg_fn ]]; then
		mapfile -t lines <"$cfg_fn"

		for (( i = 0; i < ${#lines[@]}; i++ )); do
			line="${lines[${i}]}"

			if [[ $line =~ $regex_cfg_node ]]; then
				pw_node="${BASH_REMATCH[1]}"

				break
			fi
		done

		if [[ -n $pw_node ]]; then
			match_node
		fi

# If the node name found in configuration file doesn't exist, clear
# the $pw_node variable so a new one can be created.
		if [[ -z $pw_id ]]; then
			unset -v pw_node
		fi
	fi

# If there's no configuration file, then ask the user to select audio
# output. That will get written to the configuration file.
	if [[ -z $pw_node ]]; then
		printf '\n%s\n\n' 'Select your audio output:'

		select pw_node in "${nodes[@]}"; do
			match_node

			break
		done

		if [[ -n $pw_node ]]; then
			line="node = ${pw_node}"

			printf '%s\n\n' "$line" > "$cfg_fn"
			printf '\n%s: %s\n\n' 'Wrote selected audio output to' "$cfg_fn"
		fi
	fi

	if [[ -z $pw_id ]]; then
		exit
	fi
}

# Creates a function called 'get_volume', which gets the current volume.
get_volume () {
	mapfile -t pw_dump < <(pw-dump "$pw_id" | sed -E -e 's/^[[:blank:]]*//' -e 's/[[:space:]]+/ /g')

	for (( i = 0; i < ${#pw_dump[@]}; i++ )); do
		line="${pw_dump[${i}]}"

		if [[ $line =~ $regex_volume ]]; then
			volume=$(tr -d '.' <<<"${BASH_REMATCH[1]}")

			if [[ $volume =~ $regex_zero ]]; then
				volume="${BASH_REMATCH[1]}"
			fi

			break
		fi
	done

	if [[ -z $volume ]]; then
		exit
	fi

	printf '%s' "$volume"
}

# Creates a function called 'set_volume', which sets the volume.
set_volume () {
	volume_tmp="$1"
	mute_tmp="$2"

	if [[ $volume_tmp =~ $regex_split ]]; then
		volume_1="${BASH_REMATCH[1]}"
		volume_2="${BASH_REMATCH[2]}"

		if [[ $volume_2 =~ $regex_zero ]]; then
			volume_2="${BASH_REMATCH[1]}"
		fi
	else
		volume_1=0
		volume_2="$volume_tmp"
	fi

	volume_dec=$(printf '%d.%06d' "$volume_1" "$volume_2")

	pw-cli s "$pw_id" Props "{ mute: ${mute_tmp}, channelVolumes: [ ${volume_dec}, ${volume_dec} ] }" 1>&- 2>&-
}

# Creates a function called 'reset_volume', which resets the volume.
reset_volume () {
	volume_tmp="$no_volume"

	set_volume "$volume_tmp" 'false'

	until [[ $volume_tmp -eq $full_volume ]]; do
		volume_tmp=$(( volume_tmp + 100000 ))

		if [[ $volume_tmp -gt $full_volume ]]; then
			volume_tmp="$full_volume"
		fi

		sleep 0.1

		set_volume "$volume_tmp" 'false'
	done

	printf '%s' "$volume_tmp"
}

# Creates a function called 'sleep_low', which sleeps and then lowers
# the volume.
sleep_low () {
	diff="$1"

	sleep "$interval"

	if [[ $diff -ge $volume ]]; then
		volume=0
	else
		volume=$(( volume - diff ))
	fi

	set_volume "$volume" 'false'

	printf '%s' "$volume"
}

# Creates a function called 'get_count', which will get the exact number
# to decrease the volume by every 10 seconds. Since Bash can't do
# floating-point arithmetic, this becomes slightly tricky. Keep in mind
# that Bash always rounds down, never up. I've chosen 354 as the unit
# because then it'll be exactly 1 minute left to take care of potential
# remaining value.
get_count () {
	volume_tmp="$1"

	unit=354
	count=(0 0 0)

# Calculates the difference between current volume and target volume.
	diff=$(( volume_tmp - target_volume ))

# If the difference is greater than (or equal to) 354, do some
# calculations. Otherwise just decrease by 0 until the very last second,
# and then decrease volume by the full difference. There's no need to
# lower the volume gradually, if the difference is very small.
	if [[ $diff -ge $unit ]]; then
		count[0]=$(( diff / unit ))
		rem=$(( diff % unit ))

# If there's a remaining value, then divide that value by 5, which will
# be for 354-359. If there's still a remaining value after that, then
# set ${count[2]} to that value. This will be used for the last instance
# of lowering the volume.
		if [[ $rem -ge 5 ]]; then
			count[1]=$(( rem / 5 ))
			count[2]=$(( rem % 5 ))
		else
			count[2]="$rem"
		fi
	else
		count[2]="$diff"
	fi

	printf '%s\n' "${count[@]}"
}

# Creates a function called 'spin', which will show a simple animation,
# while waiting for the command output.
spin () {
	spinner=('   ' '.  ' '.. ' '...')

	while true; do
		for s in "${spinner[@]}"; do
			printf '\r%s%s' 'Wait' "$s"
			sleep 0.5
		done
	done
}

# Gets the PipeWire id.
get_id

# Gets the volume.
volume=$(get_volume)
volume_og="$volume"

# We (re)set the original volume as full volume, cause otherwise the
# first lowering of volume is going to be much lower to the ears than
# the value set in PipeWire. The volume set in the desktop environment
# seems to be indpendent of the volume set in PipeWire, which might be
# what's causing this.
volume=$(reset_volume)

# If volume is greater than target volume, then...
if [[ $volume -gt $target_volume ]]; then
	mapfile -t count < <(get_count "$volume")

# Starts the spinner animation...
	spin &
	spin_pid="$!"

	printf '%s\n' "$volume"

# For the first 354 10-second intervals, lower the volume by the value
# in ${count[0]}
	for n in {1..354}; do
		volume=$(sleep_low "${count[0]}")
		printf '%s\n' "$volume"
	done

# For 354-359, lower the volume by the value in ${count[1]}
	for n in {1..5}; do
		volume=$(sleep_low "${count[1]}")
		printf '%s\n' "$volume"
	done

# Finally lower the volume by the value in ${count[2]}
	volume=$(sleep_low "${count[2]}")
	printf '%s\n' "$volume"

	kill "$spin_pid"
	printf '\n'
fi
