#!/bin/zsh
# name: Copy Names
# icon: textformat
# for: files
# after: copy
# description: Copies the names of the selected files

for f in "$@"; do print -r -- "${f:t}"; done
