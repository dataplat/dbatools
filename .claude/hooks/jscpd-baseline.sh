#!/bin/bash
# jscpd-baseline.sh - Generate (or --force refresh) .jscpd-baseline.json, opting
# this clone of the repo into the duplication ratchet (stop-jscpd-ratchet.sh).
#
# The baseline records the duplication that ALREADY exists, so the ratchet only
# ever blocks NEW copy-paste, never a turn that merely edits near old debt.
#
# jscpd 5.x ships a native binary per platform, so a Windows install cannot be
# reused from WSL or vice versa. When no usable jscpd is found, this script
# auto-installs one to ~/.dbatools-jscpd with npm — user-local (no sudo), and
# outside the repo tree (the repo root ships to the PowerShell Gallery, so
# node_modules must never live there).
#
# Usage:
#   bash .claude/hooks/jscpd-baseline.sh [--force] [--root <a,b>] [--min-tokens <n>]
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib-hook-common.sh"

JSCPD_VERSION="5.0.11"
FORCE=0
ROOT="public,private"
MIN_TOKENS=50

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1 ;;
        --root) ROOT="$2"; shift ;;
        --min-tokens) MIN_TOKENS="$2"; shift ;;
        *)
            echo "usage: jscpd-baseline.sh [--force] [--root <a,b>] [--min-tokens <n>]" >&2
            exit 1
            ;;
    esac
    shift
done

NODE_BIN=""
for c in node node.exe; do
    if command -v "$c" >/dev/null 2>&1; then
        NODE_BIN="$c"
        break
    fi
done
if [[ -z "$NODE_BIN" ]]; then
    echo "node is required (jscpd is a node tool). Install Node.js and retry." >&2
    exit 1
fi

REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
if [[ -z "$REPO_ROOT" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi
cd "$REPO_ROOT" || exit 1

# Make sure a platform-matching jscpd resolves; auto-install one if not.
if ! "$NODE_BIN" "$SCRIPT_DIR/lib-jscpd.js" --where >/dev/null 2>&1; then
    NPM_BIN=""
    for c in npm npm.cmd; do
        if command -v "$c" >/dev/null 2>&1; then
            NPM_BIN="$c"
            break
        fi
    done
    if [[ -z "$NPM_BIN" ]]; then
        echo "no usable jscpd found and npm is unavailable to install one." >&2
        echo "Install manually: npm install --prefix ~/.dbatools-jscpd jscpd@${JSCPD_VERSION}" >&2
        exit 1
    fi
    echo "No platform-matching jscpd found — installing jscpd@${JSCPD_VERSION} to ~/.dbatools-jscpd (user-local, no sudo)..."
    "$NPM_BIN" install --prefix "$HOME/.dbatools-jscpd" "jscpd@${JSCPD_VERSION}" || exit 1
    if ! "$NODE_BIN" "$SCRIPT_DIR/lib-jscpd.js" --where >/dev/null 2>&1; then
        echo "jscpd still does not resolve after install — see lib-jscpd.js resolution order." >&2
        exit 1
    fi
fi

echo "Scanning '$ROOT' (min-tokens $MIN_TOKENS) — this takes a while on the first run..."
BASELINE_ARGS=(--root "$ROOT" --min-tokens "$MIN_TOKENS" --baseline-out "$REPO_ROOT/.jscpd-baseline.json")
[[ $FORCE -eq 0 ]] && BASELINE_ARGS+=(--no-clobber)
exec "$NODE_BIN" "$SCRIPT_DIR/lib-jscpd.js" "${BASELINE_ARGS[@]}"
