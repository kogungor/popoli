#!/bin/zsh
# name: Email
# icon: envelope
# after: none
# match: ^\s*[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\s*$

open "mailto:${POPOLI_TEXT//[[:space:]]/}"
