#!/usr/bin/env python3
"""Clone fingerprint engine for the dbatools duplication ratchet.

Parses a jscpd JSON report (the scan itself is run by lib-jscpd.sh, because
npm's jscpd launcher is a shell script on Windows that Python cannot exec)
and derives a stable, location-independent fingerprint for every detected
clone: sha1(normalized-code-slice), computed from the byte positions jscpd
reports, so a clone keeps the same fingerprint even when unrelated edits push
it up or down in the file. Alongside each fingerprint it records the set of
files the clone spans and jscpd's clone-pair count — which is what lets the
ratchet catch a NEW copy of already-baselined code: a fresh copy adds a file
to the fingerprint's file set and/or raises its pair count.

Modes (mutually exclusive):
    --settings BASELINE                       print "<generatedFrom>\t<minTokens>"
    --baseline-out PATH --report REPORT       write baseline JSON to PATH
    --compare BASELINE --report REPORT        print "BLOCK|n" / "OK|" / "OPEN|why"

Common flags: --root DIR  --min-tokens N  --touching ABS_PATH (repeatable)
All values arrive via argv — nothing is ever interpolated into interpreter
source, and no heredoc competes with piped data.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile

_WS = re.compile(r"\s+")


def normalize(text):
    """Collapse whitespace so reformatting/indent changes don't alter the fp."""
    return _WS.sub(" ", text).strip()


def resolve_path(root_abs, name):
    """Resolve a jscpd-reported path to a real absolute file, or None.

    jscpd's `name` may be relative to the scan root, relative to cwd, or
    already absolute depending on version/config. Try the plausible bases and
    return the first that actually exists so a real file is never missed.
    """
    if not name:
        return None
    if os.path.isabs(name):
        cand = os.path.normpath(name)
        return cand if os.path.isfile(cand) else None
    for base in (root_abs, os.getcwd()):
        cand = os.path.normpath(os.path.join(base, name))
        if os.path.isfile(cand):
            return cand
    cand = os.path.normpath(name)
    return cand if os.path.isfile(cand) else None


def slice_fingerprint(abs_path, entry):
    """sha1 of the normalized code slice at abs_path named by a jscpd entry.

    Returns None when the slice cannot be read (missing file, bad offsets) so
    the caller skips it rather than crash — a fingerprint we can't compute
    must never masquerade as a match or a miss.
    """
    try:
        with open(abs_path, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except OSError:
        return None
    start = (entry.get("startLoc") or {}).get("position")
    end = (entry.get("endLoc") or {}).get("position")
    if start is None or end is None or end <= start:
        return None
    frag = normalize(content[start:end])
    if not frag:
        return None
    return hashlib.sha1(frag.encode("utf-8")).hexdigest()


def collect(report, root, touching):
    """Return {fp: {"files": [...], "pairs": N}} from a parsed jscpd report.

    Filtered to fingerprints involving any `touching` path when given, but
    each entry always carries its FULL tree-wide file set and pair count so a
    caller can compare like-for-like against a baseline.
    """
    root_abs = os.path.abspath(root)
    touching_norm = {os.path.normcase(os.path.abspath(t)) for t in (touching or [])}
    clones = {}
    touching_fps = set()
    for dup in report.get("duplicates", []):
        first = dup.get("firstFile") or {}
        second = dup.get("secondFile") or {}
        first_abs = resolve_path(root_abs, first.get("name"))
        second_abs = resolve_path(root_abs, second.get("name"))
        fp = None
        if first_abs:
            fp = slice_fingerprint(first_abs, first)
        if fp is None and second_abs:
            fp = slice_fingerprint(second_abs, second)
        if fp is None:
            continue
        rec = clones.setdefault(fp, {"files": set(), "pairs": 0})
        rec["pairs"] += 1
        for abs_path in (first_abs, second_abs):
            if abs_path:
                rec["files"].add(os.path.relpath(abs_path, root_abs).replace(os.sep, "/"))
                if touching_norm and os.path.normcase(abs_path) in touching_norm:
                    touching_fps.add(fp)
    keys = touching_fps if touching_norm else clones.keys()
    return {
        fp: {"files": sorted(clones[fp]["files"]), "pairs": clones[fp]["pairs"]}
        for fp in keys
    }


def count_new(current_clones, baseline_clones):
    """How many of current's clones are NOT accounted for by the baseline.

    New = a fingerprint the baseline never saw, OR a baselined fingerprint
    that has spread to a file the baseline didn't list, OR one whose pair
    count rose.
    """
    new = 0
    for fp, rec in current_clones.items():
        base = baseline_clones.get(fp)
        if base is None:
            new += 1
        elif set(rec.get("files", [])) - set(base.get("files", [])):
            new += 1
        elif rec.get("pairs", 0) > base.get("pairs", 0):
            new += 1
    return new


def load_report(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--report", default=None, help="path to jscpd-report.json")
    ap.add_argument("--touching", action="append", default=None)
    ap.add_argument("--min-tokens", type=int, default=75)
    ap.add_argument("--settings", default=None, help="print scan settings recorded in this baseline")
    ap.add_argument("--baseline-out", default=None, help="write baseline JSON here")
    ap.add_argument("--no-clobber", action="store_true",
                    help="refuse (atomically) to overwrite an existing baseline")
    ap.add_argument("--compare", default=None, help="baseline path to compare against")
    args = ap.parse_args()

    if args.settings:
        try:
            with open(args.settings, encoding="utf-8") as fh:
                baseline = json.load(fh)
            sys.stdout.write("%s\t%d\n" % (
                baseline.get("generatedFrom", "."),
                int(baseline.get("minTokens", args.min_tokens))))
            return 0
        except (OSError, ValueError, TypeError) as exc:
            sys.stderr.write("baseline unreadable: %s\n" % exc)
            return 1

    if not args.report:
        sys.stderr.write("--report is required for this mode\n")
        return 1
    try:
        report = load_report(args.report)
    except (OSError, ValueError) as exc:
        if args.compare:
            sys.stdout.write("OPEN|report unreadable: %s\n" % exc)
            return 0
        sys.stderr.write("report unreadable: %s\n" % exc)
        return 1

    if args.baseline_out:
        clones = collect(report, args.root, None)
        baseline = {
            "generatedFrom": args.root,
            "minTokens": args.min_tokens,
            "clones": clones,
        }
        # Atomic write: an interrupted in-place truncate would leave a corrupt
        # baseline and the ratchet would fail open indefinitely. Write a temp
        # file in the SAME directory, fsync, then publish.
        out_dir = os.path.dirname(os.path.abspath(args.baseline_out)) or "."
        fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".jscpd-baseline-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(baseline, fh, indent=2, sort_keys=True)
                fh.write("\n")
                fh.flush()
                os.fsync(fh.fileno())
            if args.no_clobber:
                # Publish via os.link, which fails atomically if the target
                # exists — no check-then-act window for concurrent runs.
                try:
                    os.link(tmp, args.baseline_out)
                except FileExistsError:
                    sys.stderr.write(
                        "refusing to overwrite existing %s (pass --force to regenerate)\n"
                        % args.baseline_out
                    )
                    return 1
            else:
                os.replace(tmp, args.baseline_out)
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        sys.stderr.write(
            "wrote %d baseline fingerprints to %s\n"
            % (len(clones), args.baseline_out)
        )
        return 0

    if args.compare:
        try:
            with open(args.compare, encoding="utf-8") as fh:
                baseline = json.load(fh)
            baseline_clones = baseline.get("clones", {})
        except (OSError, ValueError, TypeError) as exc:
            sys.stdout.write("OPEN|baseline unreadable: %s\n" % exc)
            return 0
        current = collect(report, args.root, args.touching)
        new = count_new(current, baseline_clones)
        sys.stdout.write("BLOCK|%d\n" % new if new else "OK|\n")
        return 0

    json.dump({"clones": collect(report, args.root, args.touching)}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
