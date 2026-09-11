#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for test_file in "$ROOT"/tests/*.lua
do
    lua "$test_file"
done
