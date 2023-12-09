# twimm

This is a bash script that automates the process of finding and watching long Twitch broadcasts based on desired language for language immersion. You can specify the language, resolution, game, and tags of the streamers you want to watch, and the script will parse the available videos from a custom API, save info in a text file and play random broadcasts using mpv.

## Why you shouldn't watch streams?

As you can see in a commit history, older version of this script had an option to watch streams directly. Author of this script thinks that it was a bad decision:

- Twitch streams have ads in it and even if you watch streams in `mpv` you will see an ad placeholder. If streamer is popular, this placeholder may keep for a 2+ minutes which is disturbing
- You can't seek streams but you can seek broadcasts, for example if streamer is silent (we're doing language immersion, remember?)
- Seeking a new stream is a task that requires much time for the script and for you. Just watch broadcasts, it's faster.
- Overall, streams are useless. But if you *NEED* to watch a stream, it's better to use `mpv` with your favorite streamer or check [safetwitch](https://codeberg.org/SafeTwitch/safetwitch) instances to watch Twitch safely in a browser.

## Requirements

To run this script, you need the following:

- bash
- curl
- jq
- awk
- xargs
- mpv
- A custom API instance that provides Twitch data. The default one is `projectsegfau.lt`'s one, but you can change API url by editing the `instance` variable in the script.

## Usage

You can run the script with the following options:

- `-l` Language of the streamer (Default: Español)
- `-r` Resolution of the video (Default: 480p)
- `-g` Game name (Default: Just Chatting)
- `-s` Tags to find
- `-w` Watch videos
- `-h` Display this help and exit

No flag will parse streamers and add videos to the watch list with default values.

Examples:

`./twimm.sh -s 'Argentina'`
(to get watchlist of current streamers with Argentina tag)

`./twimm.sh -l English -r 1080p60 -g 'Dota 2' -w`
(to watch English broadcast of the Dota 2 game)

## How it works

The script does the following steps:

- It creates a directory `$HOME/.local/share/twimm` to store the files related to the script, such as `tocheck`, `towatch`, `watched`, and `last_parsed`.
- It uses the `addedtags` function to search for streamers that match the tags specified by the user (or the default language) using the API. It stores the usernames of the streamers in a temporary file `streamerlist`.
- It uses the `parsingstreamers` function to parse the streamers in the `streamerlist` file and check if they have the desired language tag in their stream. It uses the API to get the streamer's login and tags, and stores them in the `favs` file, along with the language.
- It uses the `addtowatch` function to add the videos of the streamers in the `favs` file to the watch list. It uses the `comm` command to compare the `tocheck` file and the `last_parsed` file, which stores the streamers and the timestamps of the last time they were parsed. It only parses the streamers that have not been parsed recently (within 3 days). It uses the API to get the videos of the streamers, and filters them by duration (more than 10000 seconds). It stores the video id, game, login, tags, and language in the `towatch` file.
- It uses the `watch` function to watch the videos in the `towatch` file. It randomly selects a video that matches the language, tags, and game specified by the user, and gets the link to the video from the API. It uses the `mpv` command to play the video, starting from 15 minutes. It removes the video from the `towatch` file and adds it to the `watched` file. It repeats this until there are no more videos to watch or the user exits the script.

## Cron

You can add `0 * * * * /path/to/twimm.sh` line into your crontab to update your `towatch` file every hour.
