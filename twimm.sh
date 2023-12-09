#!/bin/bash
language="日本語" # 日本語, Русский, English, Español...
dir="$HOME/.local/share/twimm"
instance="${TWIMM_INSTANCE:-https://api.safetwitch.eu.projectsegfau.lt}"
#instance="https://tta.femboy.band"
resolution="480p" # 1080p60, 720p60, 480p, 360p, 160p, audio_only

tocheck="$dir/tocheck"
towatch="$dir/towatch"
watched="$dir/watched"
last_parsed_file="$dir/last_parsed"
streamerlist=$(mktemp)
toparse=$(mktemp)

days_ago=$(date -d "3 days ago" +%s)

mkdir -p "$dir"
touch "$last_parsed_file"

if [ -z "$game_orig" ] ; then
	game_orig="Just Chatting"
fi

usage() {
	echo "Usage: $0 [OPTION]..."
	echo "Automated twitch video parser"
	echo
	echo "Options:"
	echo "-l   Language of the streamer (Default: 日本語)"
	echo "-r   Resolution of the video (Default: 480p)"
	echo "-g   Game name (Default: Just Chatting)"
	echo "-s   Tags to find"
	echo "-w   Watch videos"
	echo "-h   Display this help and exit"
	echo
	echo "Examples:"
	echo "$0 -s 'Argentina'"
	echo "    (to get watchlist of current streamers with Argentina tag)"
	echo "$0 -l English -r 1080p60 -g 'Dota 2' -w"
	echo "    (to watch broadcast of the Dota 2 game)"
	exit 1
}

addedtags() {
	if [ -z "$addtags" ] ; then
		addtags="$language"
	fi
	echo "$addtags" | sed 's/|/\n/g' | while IFS= read -r line ; do
	curl -Ls "$instance/api/search/?query=$line" | jq -r '.data.channelsWithTag[] | select(.followers > 1000) | .username' >> "$streamerlist"
done
}

process_parsing() {
	local line=$1
	listofstreamers=$(curl -Ls "$instance/api/users/$line" | jq -r --arg jqLanguage "$language" '.data | select(.stream.tags[] | contains($jqLanguage)) | [ .login, (.stream.tags | join(", "))] | @tsv')
	if [ -z "$listofstreamers" ] ; then
		true
	else
		printf "%s " "$line"
		printf "%s\t%s\n" "$listofstreamers" "$language" >> "$tocheck"
	fi

}

parsingstreamers() {
	export -f process_parsing
	export instance
	export tocheck
	export language
	echo
	echo "Parsing streamers..."
	xargs -P 8 -I {} bash -c 'process_parsing "{}"' < "$streamerlist"
	awk -i inplace -F"\t" '!x[$1]++' "$tocheck"

}

process_video() {
	local all=$(grep "^$1[[:blank:]]" "$tocheck")
	local line=$(echo "$all" | awk -F'\t' '{print $1}')
	last_parsed=$(grep "^$line " "$last_parsed_file" | awk '{print $2}')
	if [ -z "$last_parsed" ] ; then
		last_parsed=0
	fi
	if [ "$last_parsed" -ge "$days_ago" ]; then
		printf "%s " "-$line"
	else
		local tags=$(echo "$all"| awk -F'\t' '{print $2}')
		local lang=$(echo "$all" | awk -F'\t' '{print $3}')
		listofvids=$(curl -Ls "$instance/api/vods/shelve/$line" | jq -r '.data[] | select(.title == "Recent broadcasts") | .videos[] | select(.duration > 10000) | {id: .id, game: .game.name, login: .streamer.login} | [.id, .game, .login] | @tsv')
		if [ -z "$listofvids" ] ; then
			true
		else
			printf "%s " "$line"
			echo "$listofvids" | sed "s/$/\t$tags\t$lang/" >> "$towatch"
		fi
		echo "$line $(date +%s)" >> "$last_parsed_file"

	fi
}

addtowatch() {
	export -f process_video
	export last_parsed_file
	export towatch
	export tocheck
	export instance
	export days_ago
	echo
	echo "Adding streamer recordings"
	comm -23 <(awk '{print $1}' "$tocheck" | sort) <(awk '{print $1}' "$last_parsed_file" | sort) >> "$toparse"
	awk -v days_ago="$days_ago" '$2 < days_ago {print $1}' "$last_parsed_file" >> "$toparse"
	sort -u "$toparse" -o "$toparse"
	xargs -P 8 -I {} bash -c 'process_video "{}"' < "$toparse"
	sort -rnk2,2 "$last_parsed_file" -o "$last_parsed_file"
	awk -i inplace '!x[$1]++' "$last_parsed_file"
	awk -i inplace -F"\t" '!x[$1]++' "$towatch"

}

watch() {
	while true ; do
		watchnow=$(cat "$towatch" | grep "${language}$" | grep -i "$addtags" | grep "$game_orig" | shuf -n1)
		if [ -z "$watchnow" ] ; then
			break
		fi
		if grep -q "$watchnow" "$watched" ; then
			sed -i "/$watchnow/d" "$towatch"
			continue
		fi
		video=$(echo "$watchnow" | awk -F'\t' '{print $1}')
		link=$(curl -Ls "$instance/proxy/vod/$video/video.m3u8"  | grep -A2 "NAME=.$resolution" | tail -n1)
		if [ -z "$link" ] ; then
			continue
		fi
		mpv --start=15:00 "$link"
		sed -i "/^$video\t/d" "$towatch"
		echo "$watchnow" >> "$watched"
		echo "Ctrl-C to exit... 10 sec"

		sleep 10
	done
}

while getopts 'l:r:g:s:wh' OPTION; do
	case "$OPTION" in
		l)
			language="$OPTARG"
			;;
		r)
			resolution="$OPTARG"
			;;
		g)
			game_orig="$OPTARG"
			;;
		s)
			addtags="$OPTARG"
			;;
		w)
			watch ;
			exit
			;;
		h)
			usage
			exit
			;;
		*)
			usage
			exit
			;;

		esac
	done

	addedtags
	parsingstreamers
	addtowatch
