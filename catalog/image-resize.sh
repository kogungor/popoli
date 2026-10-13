#!/bin/zsh
# name: Resize
# icon: arrow.down.right.and.arrow.up.left
# group: Image
# for: files
# setting: SIZE = 1600

# Saves a copy whose longest side is $SIZE pixels next to each image: photo-1600.jpg.
# Images that are already that small are left alone.
for f in "$@"; do
  size=(${(f)"$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/ {print $2}')"})
  [[ ${size[1]} == <-> && ${size[2]} == <-> ]] || { print -u2 "${f:t} is not an image"; exit 1 }
  if (( size[1] <= SIZE && size[2] <= SIZE )); then
    print -r -- "${f:t} is already ${size[1]}×${size[2]}"
    continue
  fi
  out="${f:r}-$SIZE.${f:e}"
  sips -Z "$SIZE" "$f" --out "$out" >/dev/null 2>&1 || { print -u2 "Couldn’t resize ${f:t}"; exit 1 }
  print -r -- "Created ${out:t}"
done
