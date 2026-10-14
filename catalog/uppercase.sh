#!/bin/zsh
# name: Uppercase
# icon: AB
# group: Case
# after: paste
# match: \p{Ll}
# description: Changes the selection to UPPERCASE

text=$POPOLI_TEXT
# Turkish and Azerbaijani text (it has one of their own letters): i → İ.
[[ $text == *[ğĞşŞıİəƏ]* ]] && text=${text//i/İ}
print -rn -- ${(U)text}
