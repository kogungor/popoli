#!/bin/zsh
# name: Lowercase
# icon: ab
# group: Case
# after: paste
# match: \p{Lu}
# description: Changes the selection to lowercase

text=${POPOLI_TEXT//İ/i}
# Turkish and Azerbaijani text (it has one of their own letters): I → ı.
[[ $POPOLI_TEXT == *[ğĞşŞıİəƏ]* ]] && text=${text//I/ı}
print -rn -- ${(L)text}
