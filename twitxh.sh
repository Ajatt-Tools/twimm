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

mkdir -p "$dir"
sort -u "$favs" -o "$favs"

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
	game_orig=$(cat "$gamelist" | fzf --height=10 --border-label="╢ Which game do you want to watch? ╟" --border=top --border-label-pos=3 --color=label:italic)
	game=$(echo "$game_orig" | sed 's/ /%20/g')
}


# Find streamers with more than X viewers
findstreamers () {
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
}


parsingstreamers() {
	echo "Parsing streamers..."
	while read -r line ; do
		curl -Ls "$instance/api/users/$line" | jq --arg jqLanguage "$language" '.data | select(.stream.tags[] | contains($jqLanguage)) | {login: .login, followers: .followers, title: (.stream.title | .[0:20]), viewers: .stream.viewers}' >> "$streams"
		printf "%s " "$line"
	done < "$streamerlist"
}

addtowatch() {
	while read -r line ; do
		listofvids=$(curl -Ls "$instance/api/vods/shelve/$line" | jq --arg game "$game_orig" -r '.data[] | select(.title == "All videos") | .videos[] | select(.game.name == $game) | select(.duration > 10000) | .id')
		if [ -z "$listofvids" ] ; then
			echo "No videos found, choose another user"
			sed -i "/^$watchnow |/d" "$streams"
			continue
		else
			echo "$listofvids" | sed "s/$/;$game_orig;$line/" >> "$towatch"
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
			video=$(echo "$watchnow" | awk -F';' '{print $1}')
			streamer=$(echo "$watchnow" | awk -F';' '{print $NF}')

			link=$(curl -Ls "$instance/proxy/vod/$video/video.m3u8"  | grep -A2 "NAME=.$resolution" | tail -n1)
			if [ -z "$link" ] ; then
				continue
			fi
			mpv --start=15:00 "$link"
			sed -i "/^$video;/d" "$towatch"
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

case $1 in
	-h) echo "-f favs ; -a add all to favs ; -c clips ; -cw clips watch" ;
		;;

	-c)
		clips=1
		gettinglist ;
		getgame ;
		findstreamers ;
		parsingstreamers ;
		addtowatch ;
		watch ;
		;;
	-cw)
		clips=1
		gettinglist ;
		getgame ;
		watch ;
		;;

	-a) 	gettinglist ;
		getgame ;
		findstreamers ;
		parsingstreamers ;
		cat "$streams" | jq -r '.login' >> "$favs"

		;;

	-f) streamerlist="$favs"
		parsingstreamers ;
		watch ;
		;;
	*)
		gettinglist ;
		getgame ;
		findstreamers ;
		parsingstreamers ;
		watch ;
		;;
esac
