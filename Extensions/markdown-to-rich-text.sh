#!/bin/zsh
# name: Rich Text
# icon: textformat
# output: markdown
# after: paste
# match: (?m)^(#{1,6} |[-*+] |\d+\. |> |```)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)

# Turns selected Markdown into formatted text, in place.
cat
