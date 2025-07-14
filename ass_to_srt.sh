#!/bin/bash

# Extract ASS subs from a folder (recursively) and convert them to SRT for better compatibility on Jellyfin and other media players

# CHANGELOG 1.1
# - Skip VOBSUB subtitles (cannot be converted directly to SRT without OCR first)
# - Add -l parameter to just convert files newer than X days ago (if ommitted, all files will be checked for subtitles disregarding how old they are)

# SUMMARY:
# - Identify all subtitle streams with ffmpeg/ffprobe
# - Read those lines on a while loop
# - Identify every language of every sub using grep
# - Identify if the sub is forced or not, if default
# - Format spa to es, fre to fr, eng to en
# - If it is not forced -> file.lang.srt, if forced file.lang.forced.srt, if default and forced file.lang.default.forced.srt

# EXTRA:
# - To program a daily cronjob, use this command to find all new files from last day: find /merged/rutorrent/downloads/anime_series/ -type f -name "*.mkv" -mtime -1

function ctrl_c(){
    echo -e "Exiting..."
    exit 1
}

#Ctrl+C
trap ctrl_c SIGINT

function helpPanel(){
    echo -e "\n Usage: $0 -i [ path/to/folder OR /path/to/file.mkv ] -l [last X days to review]\n"
    exit 1
}

declare -i parameter_counter=0

while getopts "i:l:h" arg; do
    case $arg in
        i) input=$OPTARG && let parameter_counter+=1;;
        l) last=$OPTARG && let parameter_counter+=1;;
        h) helpPanel
    esac
done

function convert_subs(){

        # echo "input is $input"
        curr_dir=$(echo $input | tr -d '\' 2>/dev/null)
        # echo -e "\ncurr_dir is $curr_dir\n"
        # /usr/bin/find "$curr_dir" -name "*.mkv" | # in case you wan to convert new files w/ subs added in the last 21 days fore xample, use parameter -mtime -21
        if [[ $parameter_counter == 1 ]]; then
                last="10 years ago"
        else
                last="$last days ago"
        fi
        /usr/bin/find "$curr_dir" -name "*.mkv" -newermt "$last" |
        while read LINE; do
                # echo "LINE is $LINE"
                /usr/bin/ffprobe "$LINE" > /home/minipc/scripts/ffprobe_output.txt 2>&1
                if [[ $? -ne 0 ]]; then # Continue if file is wrong (e.g., torrent with many seasons but not all are really downloaded)
                        echo -e "$LINE is wrong\n"
                        continue
                fi
                # Save absolute file name for later
                filename=$LINE
                basename=${filename::-4}
                # echo -e "\nbasename is $basename\n"
                escaped_basename="${basename// /\\ }"
                escaped_basename="${escaped_basename//\[/\\[}"
                escaped_basename="${escaped_basename//\]/\\]}"
                # echo -e "\n escaped_basename is $escaped_basename\n"
                # Use find command and check if any results were returned
                # echo -e "\n/usr/bin/find \"$curr_dir\" -type f -name \"${escaped_basename}*.srt\""
                result=$(/usr/bin/find "$curr_dir" -type f -wholename "${escaped_basename}*.srt" 2>/dev/null)
                # echo -e "\n result is $result\n"
                if [[ -n "$result" ]]; then
                    # Do something if files are found
                    echo -e "\n.srt already found for $filename, skip to the next video file\n"
                    continue
                fi
                # Determine number of first subtitle stream
                # | grep -oP ":[0-9]\(" | tr -d ':(')     ///   grep -oP ":\d:" | tr -d ':')
                first_sub_stream=$(/usr/bin/cat /home/minipc/scripts/ffprobe_output.txt | grep -m 1 -oP "Stream.*: Subtitle:" | grep -oP ":\d[:(]" | tr -d ':(')
                if [[ -z $first_sub_stream ]]; then continue; fi
                # echo -e "\nFirst sub stream is $first_sub_stream"
                # echo -e "\nTotal sub streams: $subs_streams\n"
                # Now loop through every ass subtitle
                /usr/bin/cat /home/minipc/scripts/ffprobe_output.txt | grep -Ei "Stream.*Subtitle: ass" |
                while read LINE; do
                        # echo -e "\nFile $filename has ASS subs"
                        # continue
                        # echo -e "\nLINE is $LINE\n"
                        # Find language and skip sub conversion if lang is not SPA/ENG/FRE
                        lang=$(echo $LINE | grep -oP "\([a-z]{3}\)" | tr -d "()")
                        # echo -e "\n lang is $lang\n"
                        if [[ -z $lang ]]; then # I am only interested in Spanish, English, French and (because they might be Spanish in fact) Japanese subs
                                lang=".es"
                        elif [ $lang == "spa" ]; then
                                lang=".es"
                        elif [ $lang == "eng" ]; then
                                lang=".en"
                        elif [ $lang == "fre" ]; then
                                lang=".fr"
                        elif [ $lang == "jpn" ]; then # some animes mislead jpn subs when they are indeed spa subs
                                lang=".es"
                        else
                                continue
                        fi
                        # Get index
                        let index=$(echo $LINE | grep -oP ':[0-9]' | tr -d ':')-$first_sub_stream
                        # echo -e "\n Sub index is $index\n"
                        # Find if sub is default
                        default=$(echo $LINE | grep -oP default)
                        # echo -e "\n This sub stream is $default\n"
                        if [[ ! -z "$default" ]]; then default=".$default"; fi
                        # Find if sub is forced
                        forced=$(echo $LINE | grep -oP forced)
                        # echo -e "\nThis sub stream is $forced\n"
                        if [[ ! -z "$forced" ]]; then forced=".$forced"; fi
                        # Basename -> LINE w/o .mkv extension
                        #basename=${filename::-4}
                        output="$basename$default$lang$forced.srt"
                        # echo -e "\noutput is $output \n"
                        # echo -e "\nsudo docker run --rm -v /:/config linuxserver/ffmpeg -i /config\"$filename\" -map 0:s:$index -c:s text /config\"$output\"\n"
                        # continue
                        sudo docker run --rm -v /:/config linuxserver/ffmpeg -i /config"$filename" -map 0:s:$index -c:s text /config"$output"
                done
        done

}

if [ $parameter_counter -gt 0 ]; then
        #echo "Input is $input"
        convert_subs
else
        helpPanel
fi

exit
