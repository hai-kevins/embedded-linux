#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path>"
    exit 1
fi

PATH_TO_CHECK="$1"

if [ ! -e "$PATH_TO_CHECK" ]; then
    echo "ERROR: Path does not exist: $PATH_TO_CHECK"
    exit 2
fi

echo "Path: $PATH_TO_CHECK"

if [ -f "$PATH_TO_CHECK" ]; then
    echo "Type: regular file"
elif [ -d "$PATH_TO_CHECK" ]; then
    echo "Type: directory"
else
    echo "Type: other"
fi

if [ -r "$PATH_TO_CHECK" ]; then
    echo "Readable: yes"
else
    echo "Readable: no"
fi

if [ -w "$PATH_TO_CHECK" ]; then
    echo "Writable: yes"
else
    echo "Writable: no"
fi

if [ -x "$PATH_TO_CHECK" ]; then
    echo "Executable: yes"
else
    echo "Executable: no"
fi

exit 0
