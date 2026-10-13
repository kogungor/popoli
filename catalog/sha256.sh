#!/bin/zsh
# name: SHA-256
# icon: number.square
# group: Developer

print -rn -- "$POPOLI_TEXT" | shasum -a 256 | cut -d' ' -f1
