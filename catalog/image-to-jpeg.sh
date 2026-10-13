#!/bin/zsh
# name: To JPEG
# icon: photo
# group: Image
# for: files
# description: Saves a JPEG copy of each image

for f in "$@"; do
  out="${f:r}.jpg"
  [[ -e $out ]] && out="${f:r} (JPEG).jpg"
  sips -s format jpeg -s formatOptions 85 "$f" --out "$out" >/dev/null 2>&1 || { print -u2 "${f:t} is not an image"; exit 1 }
  print -r -- "Created ${out:t}"
done
