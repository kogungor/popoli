#!/bin/zsh
# name: Call
# icon: phone
# after: none
# match: ^\s*\+?[0-9][0-9 ()./-]{5,}[0-9]\s*$

# Calls with FaceTime or iPhone, whichever macOS offers for tel: links.
open "tel:${POPOLI_TEXT//[^0-9+]/}"
