#!/bin/sh

set -e
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
