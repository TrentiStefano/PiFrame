#!/bin/bash
# usage: sheet.sh <video> <out.png> [fps=0.5]
source /c/demo/tools.sh
f=${3:-0.5}
ffmpeg -v error -y -i "$1" -vf "fps=$f,scale=640:-1,tile=3x4:padding=6:color=white" -frames:v 1 "$2"
ffprobe -v error -show_entries format=duration:stream=width,height,r_frame_rate -of csv=p=0 "$1"
