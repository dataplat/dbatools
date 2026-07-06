#!/bin/bash
# lib-jscpd.sh - Shared jscpd scan runner for the duplication ratchet.
#
# Locates a jscpd binary and a working Python, runs the scan from bash (npm's
# jscpd shim is a shell script on Windows, which Python's subprocess cannot
# exec — bash can), and leaves report parsing/fingerprinting to
# jscpd-clones.py. Callers fail open when any piece is missing.

if [[ -n "${_LIB_JSCPD_LOADED:-}" ]]; then
    return 0
fi
_LIB_JSCPD_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/lib-hook-common.sh"

JSCPD_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jscpd-clones.py"

# jscpd_locate — echo the jscpd launcher, or fail. Prefers a repo-pinned
# node_modules install, then the PATH (npm -g). $JSCPD_BIN overrides for tests.
jscpd_locate() {
    if [[ -n "${JSCPD_BIN:-}" && -e "$JSCPD_BIN" ]]; then
        printf '%s' "$JSCPD_BIN"
        return 0
    fi
    local proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    if [[ -n "$proj" && -e "$proj/node_modules/.bin/jscpd" ]]; then
        printf '%s' "$proj/node_modules/.bin/jscpd"
        return 0
    fi
    command -v jscpd 2>/dev/null
}

# jscpd_find_python — echo a WORKING python launcher ("python", "python3" or
# "py -3"); the Windows Store stub is weeded out by a real import test.
jscpd_find_python() {
    local cache="$HOOK_STATE_ROOT/python.cached" cand
    if [[ -f "$cache" ]]; then
        cand=$(cat "$cache" 2>/dev/null)
        if [[ -n "$cand" ]] && command -v "${cand%% *}" >/dev/null 2>&1; then
            printf '%s' "$cand"
            return 0
        fi
    fi
    for cand in "python" "python3" "py -3"; do
        if printf '' | $cand -c "import json, hashlib, tempfile" >/dev/null 2>&1; then
            printf '%s' "$cand" > "$cache" 2>/dev/null
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

# jscpd_native_path <path> — spelling a native (Windows) Python understands.
jscpd_native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
    else
        printf '%s' "$1"
    fi
}

# jscpd_scan <scan_root> <min_tokens> <out_dir>
# Runs jscpd with a controlled config (never an ambient repo .jscpd.json, so
# another session's config can't silently alter detection). Report lands at
# <out_dir>/jscpd-report.json. Returns nonzero on any failure.
jscpd_scan() {
    local scan_root="$1" min_tokens="$2" out_dir="$3"
    local bin config
    bin=$(jscpd_locate) || return 1
    [[ -z "$bin" ]] && return 1
    config="$out_dir/jscpd-config.json"
    cat > "$config" <<EOF
{
  "format": ["powershell", "sql", "csharp"],
  "minTokens": $min_tokens,
  "ignore": [
    "**/node_modules/**",
    "**/.git/**",
    "**/bin/**",
    "**/obj/**",
    "**/tests/**",
    "**/allcommands.ps1",
    "**/dbatools.psm1"
  ],
  "reporters": ["json"],
  "absolute": false
}
EOF
    timeout "${JSCPD_SCAN_TIMEOUT:-180}" "$bin" "$scan_root" \
        --config "$(jscpd_native_path "$config")" \
        --output "$(jscpd_native_path "$out_dir")" \
        --silent >/dev/null 2>&1
    [[ -f "$out_dir/jscpd-report.json" ]]
}
