#!/bin/zsh
# name: Copy Contents
# icon: doc.on.clipboard
# for: files
# after: copy

# Text files only, up to 2 MB in all; several files are separated by a blank line.
total=0
for f in "$@"; do
  [[ -f $f ]] || { print -u2 "${f:t} is not a file"; exit 1 }
  [[ $(file -b --mime-encoding -- "$f") == binary ]] && { print -u2 "${f:t} is not a text file"; exit 1 }
  (( total += $(stat -f %z -- "$f") ))
  (( total > 2000000 )) && { print -u2 "Too large to copy"; exit 1 }
done
first=1
for f in "$@"; do
  (( first )) || print
  first=0
  cat -- "$f"
done
