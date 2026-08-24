#!/usr/bin/env bash

REPORT="system_report.txt"

{
    echo "======================================"
    echo "       SYSTEM INFORMATION REPORT"
    echo "======================================"

    echo
    echo "[HOSTNAME]"
    hostname

    echo
    echo "[USER]"
    whoami

    echo
    echo "[DATE]"
    date

    echo
    echo "[KERNEL]"
    uname -r

    echo
    echo "[UPTIME]"
    uptime

    echo
    echo "[MEMORY]"
    free -h

    echo
    echo "[FILESYSTEM]"
    df -h

    echo
    echo "[TOP CPU PROCESSES]"
    ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 6
} > "$REPORT"

echo "Report created: $REPORT"
