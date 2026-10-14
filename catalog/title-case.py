#!/usr/bin/env python3
# name: Title Case
# icon: Aa
# group: Case
# after: paste
# match: \p{L}
# description: Capitalizes Each Word, keeping apostrophes ("Don't") and acronyms (NASA)

import re
import sys

text = sys.stdin.read()
# In text that isn't all capitals, a word in capitals is an acronym and stays as it is.
mixed = any(c.islower() for c in text)
# Turkish and Azerbaijani text (it has one of their own letters) gets their i/ı rules.
turkish = re.search("[ğĞşŞıİəƏ]", text) is not None


def upper(s):
    return (s.replace("i", "İ") if turkish else s).upper()


def lower(s):
    return (s.replace("I", "ı").replace("İ", "i") if turkish else s).lower()


def title(match):
    word = match[0]
    if mixed and len(word) > 1 and word.isupper():
        return word
    return upper(word[0]) + lower(word[1:])


print(re.sub(r"[^\W_]+(?:['’][^\W_]+)*", title, text), end="")
