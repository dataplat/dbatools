#!/bin/bash
# jscpd-baseline.sh - Generate (or refresh) the jscpd duplication baseline.
#
# The baseline records, per clone fingerprint, the files it spans and the
# number of clone-pairs jscpd saw. The Stop-gate ratchet
# (stop-jscpd-ratchet.sh) blocks a turn only when the session adds a
# fingerprint that is new, spreads a fingerprint to a new file, or raises a
# fingerprint's pair count — existing duplication the baseline records is
# fine. Pay recorded duplication down over time, then re-run this to shrink
# the allowed set: the ratchet tightens.
#
# Usage:
#   .claude/hooks/jscpd-baseline.sh [--force] [--root <dir>] [--min-tokens <n>]
#
# Requires: jscpd (npm install -g jscpd) and Python 3. Without a baseline the
# ratchet stays dormant, so running this script is how a team opts in.
set -uo pipefail

source "$(dirname "$0")/lib-jscpd.sh"

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT_DIR=$(hook_to_unix_path "$ROOT_DIR")
SCAN_ROOT="."
MIN_TOKENS="75"
FORCE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --root) SCAN_ROOT="$2"; shift 2 ;;
        --min-tokens) MIN_TOKENS="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

case "$MIN_TOKENS" in
    ''|*[!0-9]*) echo "--min-tokens must be a positive integer, got: $MIN_TOKENS" >&2; exit 1 ;;
esac

PYTHON=$(jscpd_find_python) || { echo "No working Python 3 found — install Python to use the jscpd ratchet." >&2; exit 1; }
jscpd_locate >/dev/null || { echo "jscpd not found — npm install -g jscpd (or add it to node_modules)." >&2; exit 1; }

OUT="$ROOT_DIR/.jscpd-baseline.json"
SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jscpd-baseline.XXXXXXXX") || exit 1
trap 'rm -rf "$SCAN_DIR"' EXIT

echo "Scanning $SCAN_ROOT (min-tokens $MIN_TOKENS) — this can take a minute on the full tree..."
if ! ( cd "$ROOT_DIR" && jscpd_scan "$SCAN_ROOT" "$MIN_TOKENS" "$SCAN_DIR" ); then
    echo "jscpd scan failed or timed out (JSCPD_SCAN_TIMEOUT=${JSCPD_SCAN_TIMEOUT:-180}s)." >&2
    exit 1
fi

# Overwrite protection is enforced ATOMICALLY inside the helper (--no-clobber
# publishes via os.link, which fails if the target exists). No shell -f
# check: that would be check-then-act.
NOCLOBBER=(--no-clobber)
[ "$FORCE" -eq 1 ] && NOCLOBBER=()

( cd "$ROOT_DIR" && $PYTHON "$(jscpd_native_path "$JSCPD_HELPER")" \
    --report "$(jscpd_native_path "$SCAN_DIR/jscpd-report.json")" \
    --root "$SCAN_ROOT" --min-tokens "$MIN_TOKENS" \
    --baseline-out "$(jscpd_native_path "$OUT")" "${NOCLOBBER[@]}" )
