#!/bin/bash
# libyaifdec (libyaif/yaifdec.c, the C decoder for viewer plugins): same pixels as yaif, byte for
# byte, on the files and levels of test/js.sh. Also builds it with -Wall -Werror (C99).
cd "$(dirname "$0")/.." || exit 1
gcc -std=c99 -O2 -Wall -Wextra -Werror -o libyaif/yaifdec libyaif/yaifdec_tool.c libyaif/yaifdec.c || exit 1
DEC=./libyaif/yaifdec bash test/js.sh "$@"
