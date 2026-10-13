#!/bin/zsh
# name: Color
# icon: paintpalette
# output: html
# match: ^\s*(#[0-9A-Fa-f]{3}|#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8}|(rgb|hsl)a?\([0-9.,%/ deg]*\))\s*$
# description: Shows a swatch of a hex, rgb() or hsl() color

# The match: line lets through only color characters, so the text is safe in the HTML.
color=${POPOLI_TEXT//[[:space:]]/}
print -r -- "<div style='display:flex;gap:12px;align-items:center'>
<div style='width:72px;height:44px;border-radius:10px;background:$color;box-shadow:0 0 0 1px rgba(128,128,128,.4)'></div>
<code style='font-size:14px'>$color</code></div>"
