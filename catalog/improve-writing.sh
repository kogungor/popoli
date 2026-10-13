#!/bin/zsh
# name: Improve Writing
# icon: wand.and.stars
# after: paste
# secret: ANTHROPIC_API_KEY
# setting: MODEL = claude-opus-5-5
# setting: INSTRUCTION = Improve the writing: fix grammar and spelling and make it clearer. Keep the language, meaning and tone.
# description: Rewrites the selection with Claude (needs an Anthropic API key)

# Asks Claude to rewrite the selection and puts the result in its place.
# Add your Anthropic API key in Settings ▸ Buttons ▸ Improve Writing ▸ Settings…
# (it is kept in the macOS keychain, not in this file).

prompt="$INSTRUCTION
Reply with the rewritten text only, nothing else.

<text>
$POPOLI_TEXT
</text>"

body=$(jq -n --arg model "$MODEL" --arg prompt "$prompt" \
  '{model: $model, max_tokens: 16000, fallbacks: "default", messages: [{role: "user", content: $prompt}]}')

# The key goes in through a header file, so it never shows up in the process list.
response=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H @<(print -r -- "x-api-key: $ANTHROPIC_API_KEY") \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: server-side-fallback-2026-07-01" \
  -d "$body") || { echo "Could not reach the Anthropic API" >&2; exit 1 }

error=$(print -r -- "$response" | jq -r '.error.message // empty')
[[ -n $error ]] && { echo "$error" >&2; exit 1 }
[[ $(print -r -- "$response" | jq -r '.stop_reason') == refusal ]] && { echo "Claude declined this request" >&2; exit 1 }

print -rn -- "$(print -r -- "$response" | jq -r '[.content[] | select(.type == "text") | .text] | join("")')"
