#!/usr/bin/env bash
# Run from any directory; shared by local development and CI.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
for tool in git tcsh shellcheck shfmt actionlint python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing check dependency: %s (see README.md)\n' "$tool" >&2
        exit 1
    fi
done

# NUL-separated paths preserve spaces. Include new files, exclude ignored data.
files=$(mktemp)
trap 'rm -f -- "$files"' EXIT
git ls-files -z --cached --others --exclude-standard >"$files"
while IFS= read -r -d '' file; do
    [[ -f $file && ! -L $file ]] || continue
    first_line=''
    IFS= read -r first_line <"$file" || true
    case "$first_line" in
    '#!'*csh*)
        printf 'C-shell syntax: %s\n' "$file"
        tcsh -fn "$file"
        ;;
    '#!'*bash* | '#!/bin/sh' | '#!/usr/bin/env sh')
        printf 'ShellCheck + shfmt: %s\n' "$file"
        shellcheck "$file"
        shfmt -d "$file"
        ;;
    *)
        if [[ $file == *.csh ]]; then
            printf 'C-shell syntax: %s\n' "$file"
            tcsh -fn "$file"
        fi
        ;;
    esac
done <"$files"

actionlint
python3 -m unittest discover -s tests -v
