#!/bin/zsh
# name: Base64
# icon: textformat.abc
# group: Encode
# description: Encodes the text as Base64

print -rn -- "$POPOLI_TEXT" | base64
