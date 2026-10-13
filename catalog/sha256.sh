#!/bin/zsh
# name: SHA-256
# icon: number.square
# group: Developer
# description: Shows the SHA-256 hash of the text

print -rn -- "$POPOLI_TEXT" | shasum -a 256 | cut -d' ' -f1
