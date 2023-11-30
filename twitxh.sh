#!/bin/bash
language="Español"
dir="$HOME/.local/share/twitxh"
instance="https://api.safetwitch.eu.projectsegfau.lt"
resolution="480p" # 1080p60, 720p60, 480p, 360p, 160p, audio_only
minviewers="1000"

gamelist="$dir/twitchgames"
favs="$dir/favs"
streamerlist=$(mktemp)
streams=$(mktemp)

mkdir -p "$dir"

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
	game=$(cat "$gamelist" | fzf --height=10 --border-label="╢ Which game do you want to watch? ╟" --border=top --border-label-pos=3 --color=label:italic | sed 's/ /%20/g')
}

# Find streamers with more than X viewers
findstreamers () {
	echo "Parsing streamers..."
	while true ; do
		json=$(curl -Ls "$instance/api/discover/$game?cursor=$cursor" | jq)
		streamer=$(echo "$json" | jq -r '.data.streams[].streamer.name')
		cursor=$(echo "$json" | jq -r 'last(.data.streams[].cursor)')
		echo "$streamer" >> $streamerlist
		if [ $(echo "$json" | jq -r "last(.data.streams[].viewers)") -lt $minviewers ] ; then
			break
		fi
		printf "%s " "$streamer"
	done

	sort -u "$streamerlist" -o "$streamerlist"
}

case $1 in
	-f) streamerlist="$favs"
		;;
	*)
		gettinglist ;
		getgame ;
		findstreamers ;
		;;
esac


while read -r line ; do
	curl -Ls "$instance/api/users/$line" | jq --arg jqLanguage "$language" '.data | select(.stream.tags[] | contains($jqLanguage)) | {login: .login, followers: .followers, title: (.stream.title | .[0:20]), viewers: .stream.viewers}' >> "$streams"
done < "$streamerlist"

while true ; do

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
done
