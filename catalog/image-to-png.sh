#!/bin/zsh
# name: To PNG
# icon: photo
# group: Image
# for: files

for f in "$@"; do
  out="${f:r}.png"
  [[ -e $out ]] && out="${f:r} (PNG).png"
  sips -s format png "$f" --out "$out" >/dev/null 2>&1 || { print -u2 "${f:t} is not an image"; exit 1 }
  print -r -- "Created ${out:t}"
done
