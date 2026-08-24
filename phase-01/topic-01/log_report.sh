#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

LOG_FILE="$1"

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: File not found: $LOG_FILE"
    exit 2
fi

TOTAL_LINES=$(wc -l < "$LOG_FILE")
INFO_COUNT=$(grep -c "^INFO" "$LOG_FILE")
WARN_COUNT=$(grep -c "^WARN" "$LOG_FILE")
ERROR_COUNT=$(grep -c "^ERROR" "$LOG_FILE")
LAST_ERROR=$(grep "^ERROR" "$LOG_FILE" | tail -n 1)

echo "======================================"
echo "             LOG REPORT"
echo "======================================"

echo "Log file    : $LOG_FILE"
echo "Total lines : $TOTAL_LINES"
echo "INFO count  : $INFO_COUNT"
echo "WARN count  : $WARN_COUNT"
echo "ERROR count : $ERROR_COUNT"

if [ -n "$LAST_ERROR" ]; then
    echo "Last ERROR  : $LAST_ERROR"
else
    echo "Last ERROR  : none"
fi

exit 0
