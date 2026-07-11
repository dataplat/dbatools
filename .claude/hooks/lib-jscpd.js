#!/usr/bin/env node
/* lib-jscpd.js - Shared jscpd clone engine for the duplication ratchet.
 *
 * Node port of the retired jscpd+Python engine, so the ratchet needs exactly ONE
 * runtime (node — jscpd itself already requires it) and runs identically on
 * Git Bash and Linux.
 *
 * Runs jscpd over the scan roots, parses its JSON report, and derives a stable,
 * location-independent fingerprint for every detected clone — sha1(normalized
 * code slice), taken from the EXACT position range jscpd reports, applied to
 * CRLF->LF-normalized content because that is the text jscpd computes its
 * offsets on (whole-line fallback only when an entry carries no usable
 * positions; see sliceFingerprint). A clone therefore keeps its fingerprint
 * when unrelated edits push it around the file or touch the non-cloned
 * overhang on its first/last line, and whitespace normalization makes CRLF/LF
 * spellings hash identically across platforms. Alongside each fingerprint it records the set of files the clone
 * spans and jscpd's clone-pair count, which is what lets the ratchet catch a NEW
 * copy of already-baselined code: a fresh copy adds a file to the fingerprint's
 * file set and/or raises its pair count, even though the fingerprint itself is
 * unchanged.
 *
 * Attribution (--snap-dir): the repo-wide baseline alone cannot tell WHO
 * introduced a clone — duplication that predates this session (merged from
 * upstream, made via raw Bash, or simply newer than the baseline) must not
 * block a session that merely touched the file. When the caller passes the
 * session's snapshot dir (written by pre-write-snapshot-baseline.sh), a clone
 * only blocks if some session-touched file contains MORE normalized copies of
 * the cloned fragment now than it did in its pre-write snapshot — i.e. this
 * session actually added a copy. A missing snapshot falls back to the
 * baseline-only verdict (blocking), never to a silent pass.
 *
 * This module owns ALL JSON parsing, baseline writing, and comparison so the
 * shell wrappers never interpolate values into an interpreter (no injection
 * surface). Everything is argv driven.
 *
 * jscpd 5.x ships a NATIVE binary per platform (npm picks the matching
 * cpd-<platform> package at install time), so a Windows install cannot be
 * reused from WSL or vice versa — each platform needs its own local install.
 * Resolution order (first hit wins), always spawning the package's JS launcher
 * with THIS node so PATH shims and .cmd wrappers never matter:
 *   1. $JSCPD_BIN                                  (explicit override, spawned as-is)
 *   2. $CLAUDE_PROJECT_DIR/node_modules/jscpd      (repo-local pin, if someone made one)
 *   3. ~/.dbatools-jscpd/node_modules/jscpd        (auto-installed by jscpd-baseline.sh)
 *   4. a jscpd shim's sibling node_modules on PATH, or the shim's symlink
 *      target's package dir (POSIX npm -g symlinks into .../lib/node_modules)
 * On WSL, PATH entries under /mnt/ are skipped — those are Windows installs
 * carrying the wrong platform's binary. If nothing resolves, callers fail open.
 *
 * Modes (mutually exclusive):
 *   (default)              print {"error", "clones": {...}} as JSON to stdout
 *   --baseline-out PATH    scan whole root, write baseline JSON to PATH
 *   --compare PATH         scan --touching files, print "BLOCK|n" / "OK|" / "OPEN|why"
 *   --where                print the resolved jscpd invocation after verifying it
 *                          actually runs (--version); exit 1 if none works
 *   --snap-key PATH        print the snapshot key this engine derives for PATH,
 *                          so the test suite can assert bash/node key parity on
 *                          the platform it runs on (drive-letter form included)
 *
 * Common flags: --root a,b  --min-tokens N  --touching ABS_PATH (repeatable)
 *               --snap-dir DIR (session snapshot store, enables attribution)
 */
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// The ratchet drives jscpd from THIS fixed config, never an ambient .jscpd.json
// in the repo (which another session may own and could restrict formats, change
// thresholds, or otherwise silently alter detection). Passing --config isolates
// the scan so the ratchet is deterministic regardless of repo-level jscpd config.
//
// Languages: the real source languages in this repo that jscpd tokenizes —
// powershell (.ps1/.psm1), csharp (.cs) and sql (.sql). Keep this list in
// lockstep with the extension gate in stop-jscpd-ratchet.sh.
const FORMATS = ["powershell", "csharp", "sql"];
// Bump whenever fingerprint derivation changes: fingerprints from another
// scheme silently match nothing, which would misread every old clone as new.
// A version-mismatched baseline fails OPEN with a regenerate hint instead
// (and hooks-doctor surfaces it), so stale baselines can never false-block.
// v3: positions decoded as UTF-8 byte offsets (v2 sliced UTF-16 and drifted
// on any non-ASCII text before a clone).
const FP_VERSION = 3;
const IGNORE_PATTERNS = [
    "**/node_modules/**",
    "**/bin/**",
    "**/obj/**",
    "**/tests/**",
    "**/.git/**",
    "**/.claude/**",
];
const JSCPD_TIMEOUT_MS = 200000;

function normalize(text) {
    // Collapse whitespace so reformatting/indent/EOL changes don't alter the fp.
    return text.replace(/\s+/g, " ").trim();
}

function readPackageBinScript(pkgDir) {
    // Resolve a jscpd package dir to its launcher script (bin field is either
    // "bin/jscpd" in the legacy pure-JS versions or {"jscpd": "./run-jscpd.js"}
    // in the 5.x native-binary wrapper). Returns an absolute path or null.
    let bin;
    try {
        bin = JSON.parse(fs.readFileSync(path.join(pkgDir, "package.json"), "utf8")).bin;
    } catch (e) {
        return null;
    }
    if (bin && typeof bin === "object") bin = bin.jscpd;
    if (typeof bin !== "string" || !bin) return null;
    const script = path.join(pkgDir, bin);
    return fs.existsSync(script) ? script : null;
}

function findJscpd() {
    // Returns the spawn argv prefix ([binary] or [node, launcher.js]) or null.
    const envBin = process.env.JSCPD_BIN;
    if (envBin) return fs.existsSync(envBin) ? [envBin] : null;

    const pkgDirs = [];
    if (process.env.CLAUDE_PROJECT_DIR) {
        pkgDirs.push(path.join(process.env.CLAUDE_PROJECT_DIR, "node_modules", "jscpd"));
    }
    pkgDirs.push(path.join(os.homedir(), ".dbatools-jscpd", "node_modules", "jscpd"));
    for (const dir of (process.env.PATH || "").split(path.delimiter)) {
        if (!dir) continue;
        // WSL: /mnt/* PATH entries are Windows npm installs whose native cpd
        // binary is the wrong platform — running it would only fail open noisily.
        if (process.platform !== "win32" && dir.startsWith("/mnt/")) continue;
        for (const shim of ["jscpd", "jscpd.cmd"]) {
            const shimPath = path.join(dir, shim);
            if (!fs.existsSync(shimPath)) continue;
            // Windows npm keeps the package right next to the shim; POSIX npm -g
            // symlinks the shim into .../lib/node_modules/jscpd — resolve the
            // link and walk back to the package dir so both layouts are found.
            pkgDirs.push(path.join(dir, "node_modules", "jscpd"));
            try {
                const target = fs.realpathSync(shimPath).replace(/\\/g, "/");
                const m = target.match(/^(.*\/node_modules\/jscpd)\//);
                if (m) pkgDirs.push(m[1]);
            } catch (e) { /* dangling symlink — other candidates may still work */ }
        }
    }
    for (const pkgDir of pkgDirs) {
        const script = readPackageBinScript(pkgDir);
        if (!script) continue;
        // An install that EXISTS can still be broken — most plausibly a
        // node_modules synced from the other OS on a Windows/WSL-shared
        // checkout, carrying the wrong platform's native cpd binary. Probe
        // before committing, so a dead higher-priority candidate falls
        // through to a working one instead of failing every scan open.
        const probe = spawnSync(process.execPath, [script, "--version"], { stdio: "ignore", timeout: 30000 });
        if (probe.error || probe.status !== 0) continue;
        return [process.execPath, script];
    }
    return null;
}

function resolvePath(rootsAbs, name) {
    // Resolve a jscpd-reported path to a real absolute file, or null. jscpd's
    // `name` may be absolute (we ask for absolute:true), relative to a scan
    // root, or relative to cwd depending on version — try the plausible bases
    // so a real file is never silently dropped (which would fail open).
    if (!name) return null;
    const norm = name.replace(/\\/g, "/");
    if (path.isAbsolute(norm) || /^[A-Za-z]:\//.test(norm)) {
        const cand = path.normalize(norm);
        return fs.existsSync(cand) && fs.statSync(cand).isFile() ? cand : null;
    }
    for (const base of [...rootsAbs, process.cwd()]) {
        const cand = path.normalize(path.join(base, norm));
        if (fs.existsSync(cand) && fs.statSync(cand).isFile()) return cand;
    }
    return null;
}

function sliceFingerprint(absPath, entry) {
    // sha1 + normalized text of the EXACT clone range at absPath named by a
    // jscpd entry. jscpd computes `position` offsets on newline-normalized
    // text, so the content is CRLF->LF normalized before slicing — the offsets
    // then address the precise token range on every platform. Exact ranges
    // (never whole lines) matter twice over: the fingerprint must not change
    // when someone edits the NON-cloned overhang sharing the clone's first or
    // last line, and attribution must count occurrences of the clone itself,
    // not clone-plus-neighbors. Falls back to the whole-line range when a
    // report entry carries no usable positions. Returns null when the slice
    // cannot be read so the caller skips it rather than crash — a fingerprint
    // we can't compute must never masquerade as a match or a miss.
    let content;
    try {
        content = fs.readFileSync(absPath, "utf8").replace(/\r\n/g, "\n");
    } catch (e) {
        return null;
    }
    // Positions are UTF-8 BYTE offsets (verified empirically: with multi-byte
    // text before a clone, only byte-space slicing aligns both sides of the
    // pair), so slice the UTF-8 buffer, never the UTF-16 string — String.slice
    // drifts on every non-ASCII character and corrupts the fragment.
    let raw = null;
    const buf = Buffer.from(content, "utf8");
    const start = entry && entry.startLoc ? entry.startLoc.position : undefined;
    const end = entry && entry.endLoc ? entry.endLoc.position : undefined;
    if (typeof start === "number" && typeof end === "number" && start >= 0 && end > start && end <= buf.length) {
        raw = buf.subarray(start, end).toString("utf8");
    } else {
        const startLine = entry && entry.startLoc ? entry.startLoc.line : undefined;
        const endLine = entry && entry.endLoc ? entry.endLoc.line : undefined;
        if (typeof startLine !== "number" || typeof endLine !== "number" || endLine < startLine || startLine < 1) return null;
        raw = content.split("\n").slice(startLine - 1, endLine).join("\n");
    }
    const frag = normalize(raw);
    if (!frag) return null;
    return { fp: crypto.createHash("sha1").update(frag, "utf8").digest("hex"), frag: frag };
}

function runJscpd(rootsAbs, minTokens, outDir) {
    // Run the resolved jscpd; return the parsed report object or null on failure.
    const argv = findJscpd();
    if (argv === null) return null;
    const configPath = path.join(outDir, "jscpd-config.json");
    const config = {
        format: FORMATS,
        minTokens: minTokens,
        ignore: IGNORE_PATTERNS,
        reporters: ["json"],
        absolute: true,
    };
    try {
        fs.writeFileSync(configPath, JSON.stringify(config));
    } catch (e) {
        return null;
    }
    const result = spawnSync(argv[0], [
        ...argv.slice(1),
        ...rootsAbs,
        "--config", configPath,
        "--output", outDir,
        "--silent",
    ], { stdio: "ignore", timeout: JSCPD_TIMEOUT_MS });
    if (result.error) return null;
    try {
        return JSON.parse(fs.readFileSync(path.join(outDir, "jscpd-report.json"), "utf8"));
    } catch (e) {
        return null;
    }
}

function repoRel(abs) {
    return path.relative(process.cwd(), abs).replace(/\\/g, "/");
}

function collect(roots, minTokens, touching) {
    // Returns {error, clones: {fp: {files: [...], pairs: N[, frag]}}}. clones
    // is filtered to fingerprints involving a `touching` file when given (and
    // then each entry carries the normalized cloned fragment for attribution),
    // but every entry always carries its FULL tree-wide file set and pair
    // count so a caller can compare like-for-like against a baseline.
    const rootsAbs = roots.map((r) => path.resolve(r));
    const touchingAbs = new Set((touching || []).map((t) => canonicalAbs(t)));

    let outDir;
    let report;
    try {
        outDir = fs.mkdtempSync(path.join(os.tmpdir(), "jscpd-"));
        report = runJscpd(rootsAbs, minTokens, outDir);
    } finally {
        if (outDir) fs.rmSync(outDir, { recursive: true, force: true });
    }
    if (report === null) return { error: "jscpd-unavailable", clones: {} };

    const clones = {}; // fp -> {files: Set, pairs: int, frags: {rel: [text]}}, tree-wide
    const touchingFps = new Set();
    for (const dup of report.duplicates || []) {
        const first = dup.firstFile || {};
        const second = dup.secondFile || {};
        // Resolve each reported path to a real file ONCE, then reuse the
        // absolute path for both reading and touch-matching, and a canonical
        // repo-relative forward-slash form for the stored file set (so
        // baselines written on Windows and Linux agree exactly).
        const firstAbs = resolvePath(rootsAbs, first.name);
        const secondAbs = resolvePath(rootsAbs, second.name);
        // Slice BOTH sides: exact-range fragments are normally identical
        // across the pair, but report entries can be asymmetric (one side
        // unreadable, position fallback to whole lines on one side only), so
        // attribution always compares a touched file against ITS OWN fragment
        // — a literal substring of that file by construction — never the
        // other side's. The fingerprint stays derived from the first readable
        // side, exactly as the baseline format always has.
        const hitFirst = firstAbs ? sliceFingerprint(firstAbs, first) : null;
        const hitSecond = secondAbs ? sliceFingerprint(secondAbs, second) : null;
        const hit = hitFirst || hitSecond;
        if (hit === null) continue;
        const rec = clones[hit.fp] || (clones[hit.fp] = { files: new Set(), pairs: 0, frags: {} });
        rec.pairs += 1;
        for (const [abs, sideHit] of [[firstAbs, hitFirst], [secondAbs, hitSecond]]) {
            if (!abs) continue;
            const rel = repoRel(abs);
            rec.files.add(rel);
            if (sideHit) (rec.frags[rel] = rec.frags[rel] || []).push(sideHit.frag);
            if (touchingAbs.has(canonicalAbs(abs))) touchingFps.add(hit.fp);
        }
    }

    const keys = touchingAbs.size ? touchingFps : Object.keys(clones);
    const out = {};
    for (const fp of keys) {
        out[fp] = { files: [...clones[fp].files].sort(), pairs: clones[fp].pairs };
        // Fragments are only needed for attribution against snapshots, which
        // only happens in touching mode — keep baselines lean and stable.
        if (touchingAbs.size) out[fp].frags = clones[fp].frags;
    }
    return { error: null, clones: out };
}

// ---------------------------------------------------------------- attribution
function canonicalAbs(p) {
    // Match the canonical form pre-write-snapshot-baseline.sh keys on:
    // realpath when resolvable, plain resolution otherwise.
    try {
        return fs.realpathSync(path.resolve(p));
    } catch (e) {
        return path.resolve(p);
    }
}

function snapshotKey(absPath) {
    // Same derivation as the snapshot hook: sha1 of the canonical path,
    // forward slashes, lowercased only on case-insensitive Windows. On
    // Windows the hook runs under Git Bash where realpath speaks /c/x while
    // node speaks C:/x — convert to the Git Bash spelling before hashing or
    // producer and consumer derive different keys and attribution silently
    // falls back to blocking. (--snap-key exposes this for the test suite.)
    let p = absPath.replace(/\\/g, "/");
    if (process.platform === "win32") {
        p = p.replace(/^([A-Za-z]):\//, (m, drive) => "/" + drive + "/").toLowerCase();
    }
    return crypto.createHash("sha1").update(p, "utf8").digest("hex");
}

function snapshotContent(snapDir, absPath) {
    // Pre-write content of absPath as snapshotted at first touch this session;
    // "" for a file the session created (empty baseline), null when unknown.
    try {
        return fs.readFileSync(path.join(snapDir, snapshotKey(absPath) + ".base"), "utf8");
    } catch (e) {
        return null;
    }
}

function countOccurrences(hay, needle) {
    if (!needle) return 0;
    let n = 0;
    let i = hay.indexOf(needle);
    while (i !== -1) {
        n += 1;
        i = hay.indexOf(needle, i + needle.length);
    }
    return n;
}

function baselineAccounts(rec, base, touchedRelSet) {
    // Does the repo-wide baseline already account for this clone?
    // Spread matters only when it lands in a file THIS session touched — a
    // copy some other session added elsewhere is not this turn's doing (and a
    // genuine foreign copy still raises the pair count, so nothing hides).
    if (!base) return false;
    const spreadToTouched = (rec.files || []).some(
        (f) => !(base.files || []).includes(f) && touchedRelSet.has(f)
    );
    if (spreadToTouched) return false;
    if ((rec.pairs || 0) > (base.pairs || 0)) return false;
    return true;
}

function snapshotVerdict(rec, ctx) {
    // Per-clone attribution against this session's pre-write snapshots:
    //   "added"     — some touched file the clone involves holds MORE
    //                 normalized copies of its fragment now than in its
    //                 pre-write snapshot: this session pasted a copy.
    //   "not-added" — every touched involved file has a snapshot and none
    //                 gained a copy.
    //   "unknown"   — attribution impossible (no snapshot store, no per-side
    //                 fragment, missing snapshot, unreadable file, or the
    //                 clone involves no touched file).
    // Each touched file is compared against ITS OWN recorded fragments
    // (report entries can be asymmetric — an unreadable side, or a whole-line
    // fallback on one side only — so the other side's text may legitimately
    // occur zero times here).
    // Never conclude "unknown" from the FIRST gap: scan every touched involved
    // file, because a later one may hold snapshot PROOF of an added copy —
    // "added" must win over "unknown" or an attribution gap in one file lets
    // a proven paste in another escape the baseline-offset scenarios.
    if (!ctx.snapDir) return "unknown";
    let sawSnapshot = false;
    let sawUnknown = false;
    for (const abs of ctx.touchedAbs) {
        const rel = repoRel(abs);
        if (!(rec.files || []).includes(rel)) continue;
        const sideFrags = (rec.frags || {})[rel];
        if (!sideFrags || !sideFrags.length) {
            sawUnknown = true;
            continue;
        }
        const snap = snapshotContent(ctx.snapDir, abs);
        if (snap === null) {
            sawUnknown = true;
            continue;
        }
        let current;
        try {
            current = fs.readFileSync(abs, "utf8");
        } catch (e) {
            sawUnknown = true;
            continue;
        }
        sawSnapshot = true;
        const currentNorm = normalize(current);
        const snapNorm = normalize(snap);
        for (const frag of sideFrags) {
            if (countOccurrences(currentNorm, frag) > countOccurrences(snapNorm, frag)) {
                return "added";
            }
        }
    }
    if (sawUnknown || !sawSnapshot) return "unknown";
    return "not-added";
}

function countNew(currentClones, baselineClones, ctx) {
    // How many of current's clones are NEW WORK OF THIS SESSION. Snapshot
    // attribution outranks aggregate baseline accounting in BOTH directions:
    // a proven session-added copy blocks even when an unrelated removal
    // elsewhere keeps the tree-wide file set and pair count at baselined
    // levels, and a provenly pre-existing clone passes even when the baseline
    // missed it. Only an "unknown" falls back to the baseline-only verdict,
    // so attribution gaps can never grant a silent pass.
    let n = 0;
    for (const [fp, rec] of Object.entries(currentClones)) {
        const verdict = snapshotVerdict(rec, ctx);
        if (verdict === "added") {
            n += 1;
        } else if (verdict === "unknown" && !baselineAccounts(rec, baselineClones[fp], ctx.touchedRelSet)) {
            n += 1;
        }
    }
    return n;
}

function parseArgs(argv) {
    const args = {
        root: "public,private",
        minTokens: 50,
        touching: [],
        snapDir: null,
        baselineOut: null,
        noClobber: false,
        compare: null,
        where: false,
        snapKey: null,
        fpVersion: false,
    };
    for (let i = 0; i < argv.length; i++) {
        switch (argv[i]) {
            case "--root": args.root = argv[++i]; break;
            case "--min-tokens": args.minTokens = parseInt(argv[++i], 10); break;
            case "--touching": args.touching.push(argv[++i]); break;
            case "--snap-dir": args.snapDir = argv[++i]; break;
            case "--baseline-out": args.baselineOut = argv[++i]; break;
            case "--no-clobber": args.noClobber = true; break;
            case "--compare": args.compare = argv[++i]; break;
            case "--where": args.where = true; break;
            case "--snap-key": args.snapKey = argv[++i]; break;
            case "--fp-version": args.fpVersion = true; break;
            default:
                process.stderr.write(`lib-jscpd.js: unknown argument ${argv[i]}\n`);
                process.exit(1);
        }
    }
    if (!Number.isInteger(args.minTokens) || args.minTokens <= 0) args.minTokens = 50;
    return args;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const roots = args.root.split(",").map((r) => r.trim()).filter(Boolean);

    if (args.where) {
        // Report only an invocation that actually RUNS: an existing-but-broken
        // binary (wrong platform, $JSCPD_BIN=/bin/false) must read as absent,
        // or hooks-doctor reports green while every scan fails open.
        const argv = findJscpd();
        if (argv === null) return 1;
        const probe = spawnSync(argv[0], [...argv.slice(1), "--version"], { stdio: "ignore", timeout: 30000 });
        if (probe.error || probe.status !== 0) return 1;
        process.stdout.write(argv.join(" ") + "\n");
        return 0;
    }

    if (args.snapKey) {
        process.stdout.write(snapshotKey(canonicalAbs(args.snapKey)) + "\n");
        return 0;
    }

    if (args.fpVersion) {
        process.stdout.write(FP_VERSION + "\n");
        return 0;
    }

    if (args.baselineOut) {
        const result = collect(roots, args.minTokens, null);
        if (result.error) {
            process.stderr.write(`jscpd baseline generation failed: ${result.error}\n`);
            return 1;
        }
        const baseline = {
            generatedFrom: roots.join(","),
            minTokens: args.minTokens,
            fingerprintVersion: FP_VERSION,
            clones: result.clones,
        };
        // Atomic publish: an interrupted in-place truncate would leave a corrupt
        // baseline, and the hook would then fail open indefinitely. Write to a
        // temp file in the SAME directory, then publish. --no-clobber publishes
        // via link(2), which fails atomically if the target already exists; where
        // hardlinks aren't supported (some WSL drvfs mounts) fall back to
        // COPYFILE_EXCL — also exclusive, so two concurrent runs can never both
        // win. Random temp name + "wx" (O_CREAT|O_EXCL) keeps a pre-planted
        // symlink from redirecting the write.
        const outAbs = path.resolve(args.baselineOut);
        const tmp = path.join(
            path.dirname(outAbs),
            `.jscpd-baseline-${crypto.randomBytes(8).toString("hex")}.tmp`
        );
        try {
            fs.writeFileSync(tmp, JSON.stringify(sortKeysDeep(baseline), null, 2) + "\n", { flag: "wx" });
            if (args.noClobber) {
                try {
                    // JSCPD_TEST_NO_LINK is a test-suite-only knob: hardlinks
                    // work on every filesystem the tests run on, so the
                    // COPYFILE_EXCL fallback would otherwise be untestable.
                    if (process.env.JSCPD_TEST_NO_LINK === "1") {
                        const err = new Error("test-forced link failure");
                        err.code = "ENOTSUP";
                        throw err;
                    }
                    fs.linkSync(tmp, outAbs);
                } catch (e) {
                    if (e.code === "EEXIST") {
                        process.stderr.write(`refusing to overwrite existing ${args.baselineOut} (pass --force to regenerate)\n`);
                        return 1;
                    }
                    try {
                        fs.copyFileSync(tmp, outAbs, fs.constants.COPYFILE_EXCL);
                    } catch (e2) {
                        if (e2.code === "EEXIST") {
                            process.stderr.write(`refusing to overwrite existing ${args.baselineOut} (pass --force to regenerate)\n`);
                            return 1;
                        }
                        throw e2;
                    }
                }
            } else {
                fs.renameSync(tmp, outAbs);
            }
        } finally {
            fs.rmSync(tmp, { force: true });
        }
        process.stderr.write(`wrote ${Object.keys(result.clones).length} baseline fingerprints to ${args.baselineOut}\n`);
        return 0;
    }

    if (args.compare) {
        // Load the baseline FIRST and scan with the exact settings it was built
        // with. jscpd's clone set is sensitive to min-tokens and scan roots, so
        // comparing a scan taken at different settings could miss new duplicates
        // or flag pre-existing ones. The baseline is the source of truth.
        let baseline;
        try {
            baseline = JSON.parse(fs.readFileSync(args.compare, "utf8"));
        } catch (e) {
            process.stdout.write(`OPEN|baseline unreadable: ${e.message}\n`);
            return 0;
        }
        const baseV = baseline.fingerprintVersion || 1;
        if (baseV !== FP_VERSION) {
            process.stdout.write(`OPEN|baseline fingerprint scheme v${baseV} != engine v${FP_VERSION} — regenerate: bash .claude/hooks/jscpd-baseline.sh --force\n`);
            return 0;
        }
        const baselineClones = baseline.clones || {};
        const scanRoots = String(baseline.generatedFrom || args.root).split(",").map((r) => r.trim()).filter(Boolean);
        const minTokens = parseInt(baseline.minTokens, 10) || args.minTokens;
        const result = collect(scanRoots, minTokens, args.touching);
        if (result.error) {
            process.stdout.write(`OPEN|jscpd unavailable: ${result.error}\n`);
            return 0;
        }
        const touchedAbs = args.touching.map(canonicalAbs);
        const ctx = {
            snapDir: args.snapDir && fs.existsSync(args.snapDir) ? args.snapDir : null,
            touchedAbs: touchedAbs,
            touchedRelSet: new Set(touchedAbs.map(repoRel)),
        };
        const fresh = countNew(result.clones, baselineClones, ctx);
        process.stdout.write(fresh ? `BLOCK|${fresh}\n` : "OK|\n");
        return 0;
    }

    const result = collect(roots, args.minTokens, args.touching.length ? args.touching : null);
    process.stdout.write(JSON.stringify(result) + "\n");
    return 0;
}

function sortKeysDeep(value) {
    // Recursively sorted keys, so baselines serialize identically run-to-run.
    if (Array.isArray(value)) {
        return value.map(sortKeysDeep);
    }
    if (value && typeof value === "object") {
        const out = {};
        for (const k of Object.keys(value).sort()) {
            out[k] = sortKeysDeep(value[k]);
        }
        return out;
    }
    return value;
}

process.exit(main());
