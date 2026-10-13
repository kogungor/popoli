#!/bin/zsh
# name: SHA-256
# icon: number.square
# for: files

for f in "$@"; do
  [[ -f $f ]] || continue
  print -r -- "$(shasum -a 256 -- "$f" | cut -d' ' -f1)  ${f:t}"
done
