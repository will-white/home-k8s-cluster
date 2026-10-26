#!/usr/bin/env bash
# Bazarr post-processing hook: Settings > Subtitles > Post-Processing command
#   /scripts/subcleaner.sh "{{subtitles}}"
# Plex is refreshed by Bazarr's own Plex integration, not here.

printf "Cleaning subtitles for '%s' ...\n" "$1"
python3 /add-ons/subcleaner/subcleaner.py "$1" -s
