#!/usr/bin/env bash
# Capture stdout/stderr, optionally mirror them, and preserve tool failures.
set -uo pipefail

if [[ $# -lt 3 ]]; then
    printf 'Usage: %s --quiet|--verbose LOG COMMAND [ARGS...]\n' "$0" >&2
    exit 2
fi
output_mode=$1
log_path=$2
shift 2
case "$output_mode" in
--quiet)
    exec "$@" >"$log_path" 2>&1
    ;;
--verbose)
    # Open the log before launching a potentially expensive tool.
    if ! : >"$log_path"; then
        exit 1
    fi
    "$@" 2>&1 | tee -a "$log_path"
    exit_codes=("${PIPESTATUS[@]}")
    if ((exit_codes[0] != 0)); then
        exit "${exit_codes[0]}"
    fi
    exit "${exit_codes[1]}"
    ;;
*)
    printf 'Unknown logging mode: %s\n' "$output_mode" >&2
    exit 2
    ;;
esac
