#!/bin/zsh
# name: Word Count
# icon: number
# description: Counts the words and characters in the selection

words=$(print -rn -- "$POPOLI_TEXT" | wc -w | tr -d ' ')
chars=$(print -rn -- "$POPOLI_TEXT" | wc -m | tr -d ' ')
echo "$words words · $chars characters"
