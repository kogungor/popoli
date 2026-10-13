#!/bin/zsh
# name: Copy Names
# icon: textformat
# for: files
# after: copy

for f in "$@"; do print -r -- "${f:t}"; done
