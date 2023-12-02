#!/bin/bash
language="Español" # 日本語, Русский, English, Español...
dir="$HOME/.local/share/twitxh"
instance="https://api.safetwitch.eu.projectsegfau.lt"
resolution="480p" # 1080p60, 720p60, 480p, 360p, 160p, audio_only
minviewers="500"

gamelist="$dir/twitchgames"
favs="$dir/favs"
towatch="$dir/towatch"
watched="$dir/watched"
blacklist="$dir/blacklist"
streamerlist=$(mktemp)
streams=$(mktemp)
find_done=0
parsing_done=0

mkdir -p "$dir"
sort -u "$favs" -o "$favs"


usage() {
	echo "Usage: $(basename $0) [OPTIONS]"
	echo "This script allows you to watch (mostly random) streams and videos from Twitch."
	echo
	echo "Options:"
	echo "  -l language    Define the language (default: Español)"
	echo "  -r resolution  Define the resolution (default: 480p)"
	echo "  -g game        Define the game (default: asks with fzf)"
	echo "  -c             Parse clips"
	echo "  -w             Watch random clips from parsed list"
	echo "  -f             Check favs' live"
	echo "  -a             Parse streamers and add all to favs"
	echo "  -h             Display this help message"
	echo
	echo "Examples:"
	echo "  $(basename $0) -l English -r 720p        Set language to English and resolution to 720p"
	echo "  $(basename $0) -c                        Enable clips"
	echo "  $(basename $0) -f                        Use favs"
	echo "  $(basename $0) -a                        Add all to favs"
	exit 1
}


# Getting list of games

gettinglist() {
	if [ ! -f "$gamelist" ] ; then
		echo "Loading games list..."
		while true ; do
			json=$(curl -Ls "$instance/api/discover?cursor=$cursor" | jq)
			if [ $(echo "$json" | jq -r 'last(.data[].viewers)') -lt 100 ] ; then
				break
			fi
			games=$(echo "$json" | jq -r '.data[].name')
			cursor=$(echo "$json" | jq -r 'last(.data[].cursor)')
			echo "$games" >> $gamelist
		done
	fi

	unset cursor

}

# Get game
getgame() {

	if [ -z "$game_orig" ] ; then
		game_orig=$(cat "$gamelist" | fzf --height=10 --border-label="╢ Which game do you want to watch? ╟" --border=top --border-label-pos=3 --color=label:italic)
	fi

	game=$(echo "$game_orig" | sed 's/ /%20/g')
}


# Find streamers with more than X viewers
findstreamers () {
	if [ "$find_done" -eq 1 ] ; then
		true
	else
		echo "Looking for streamers..."
		while true ; do
			json=$(curl -Ls "$instance/api/discover/$game?cursor=$cursor" | jq)
			streamers=$(echo "$json" | jq -r '.data.streams[].streamer.name')
			cursor=$(echo "$json" | jq -r 'last(.data.streams[].cursor)')
			echo "$streamers" >> $streamerlist
			if [ $(echo "$json" | jq -r "last(.data.streams[].viewers)") -lt $minviewers ] ; then
				break
			fi
		done

		sort -u "$streamerlist" -o "$streamerlist"
	fi
	find_done=1
}

parsingstreamers() {
	if [ "$parsing_done" -eq 1 ] ; then
		true
	else
		echo "Parsing streamers..."
		while read -r line ; do
			curl -Ls "$instance/api/users/$line" | jq --arg jqLanguage "$language" '.data | select(.stream.tags[] | contains($jqLanguage)) | {login: .login, followers: .followers, title: (.stream.title | .[0:20]), viewers: .stream.viewers}' >> "$streams"
			printf "%s " "$line"
		done < "$streamerlist"
	fi
	parsing_done=1
}

addtowatch() {
	while read -r line ; do
		listofvids=$(curl -Ls "$instance/api/vods/shelve/$line" | jq --arg game "$game_orig" -r '.data[] | select(.title == "All videos") | .videos[] | select(.duration > 10000) | {id: .id, game: .game.name, login: .streamer.login} | [.id, .game, .login] | @tsv')
		if [ -z "$listofvids" ] ; then
			continue
		else
			echo "$listofvids" >> "$towatch"
		fi
		sort -u "$towatch" -o "$towatch"


	done <<< "$(cat "$streams" | jq -r '.login' && cat "$favs")"
}

watch() {
	while true ; do
		if [ "$clips" -eq 1 ] ; then
			watchnow=$(cat "$towatch" | grep "$game_orig" | shuf -n1)
			if [ -z "$watchnow" ] ; then
				break
			fi
			if grep -q "$watchnow" "$watched" ; then
				sed -i "/$watchnow/d" "$towatch"
				continue
			fi
			video=$(echo "$watchnow" | awk -F'\t' '{print $1}')
			streamer=$(echo "$watchnow" | awk -F'\t' '{print $NF}')

			link=$(curl -Ls "$instance/proxy/vod/$video/video.m3u8"  | grep -A2 "NAME=.$resolution" | tail -n1)
			if [ -z "$link" ] ; then
				continue
			fi
			mpv --start=15:00 "$link"
			sed -i "/^$video\t/d" "$towatch"
			echo "$watchnow" >> "$watched"
			echo "Ctrl-C to exit... 10 sec"

		else
			watchnow=$(cat "$streams" | jq -r '[.login, .followers, .title, .viewers] | @tsv' | column -s$'\t' -t -o' | ' | awk '{print $NF,$0}' | sort -nr | cut -f2- -d' ' | fzf --height=10 --border-label="╢ Which streamer do you want to watch? ╟" --border=top --border-label-pos=3 --color=label:italic | awk -F' | ' '{print $1}')
			link=$(curl "$instance/proxy/stream/$watchnow/hls.m3u8" | grep -A2 "NAME=.$resolution" | tail -n1)
			mpv "$link"
			fav=$(printf "%s\n%s\n" "No" "Yes" | fzf --height=10 --border-label="╢ Do you want to add this streamer to favs? ╟" --border=top --border-label-pos=3 --color=label:italic)

			if [ "$fav" == "Yes" ] ; then
				echo "$watchnow" >> "$favs"
			fi

			more=$(printf "%s\n%s\n" "No" "Yes" | fzf --height=10 --border-label="╢ Do you want to watch another streamer? ╟" --border=top --border-label-pos=3 --color=label:italic)

			if [ "$more" == "No" ] ; then
				break
			fi
		fi





	# streamlink -p mpv --twitch-low-latency "https://twitch.tv/$watchnow" "$resolution"


	unset fav more

	sleep 10
done
}






while getopts 'l:r:g:cwfah' OPTION; do
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
		c)
			clips=1
			gettinglist ;
			getgame ;
			findstreamers ;
			parsingstreamers ;
			addtowatch ;

			;;
		w)
			clips=1
			gettinglist ;
			getgame ;
			watch ;
			;;

		f)
			streamerlist="$favs"
			parsingstreamers
			watch
			exit
			;;
		a)
			gettinglist
			getgame
			findstreamers
			parsingstreamers
			cat "$streams" | jq -r '.login' >> "$favs"
			exit
			;;
		h)
			usage
			;;
		*)
			gettinglist ;
			getgame ;
			findstreamers ;
			parsingstreamers ;
			watch ;
			;;
	esac
done
