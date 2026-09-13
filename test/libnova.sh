#!/bin/bash
# libnovadec (libnova/novadec.c, the C decoder for viewer plugins): same pixels as nova, byte for
# byte, on the files and levels of test/js.sh. Also builds it with -Wall -Werror (C99).
cd "$(dirname "$0")/.." || exit 1
gcc -std=c99 -O2 -Wall -Wextra -Werror -o libnova/novadec libnova/novadec_tool.c libnova/novadec.c || exit 1
DEC=./libnova/novadec bash test/js.sh "$@"
