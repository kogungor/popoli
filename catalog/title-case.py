#!/usr/bin/env python3
# name: Title Case
# icon: Aa
# after: paste
# description: Changes the selection to Title Case

import sys

print(sys.stdin.read().title(), end="")
