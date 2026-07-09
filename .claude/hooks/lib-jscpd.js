#!/usr/bin/env node
/* lib-jscpd.js - Shared jscpd clone engine for the duplication ratchet.
 *
 * Node port of the retired jscpd+Python engine, so the ratchet needs exactly ONE
 * runtime (node — jscpd itself already requires it) and runs identically on
 * Git Bash and Linux.
 *
 * Runs jscpd over the scan roots, parses its JSON report, and derives a stable,
 * location-independent fingerprint for every detected clone — sha1(normalized
 * code slice), computed from the byte positions jscpd reports, so a clone keeps
 * the same fingerprint even when unrelated edits push it up or down in the file
 * (and whitespace normalization makes CRLF/LF spellings hash identically across
 * platforms). Alongside each fingerprint it records the set of files the clone
 * spans and jscpd's clone-pair count, which is what lets the ratchet catch a NEW
 * copy of already-baselined code: a fresh copy adds a file to the fingerprint's
 * file set and/or raises its pair count, even though the fingerprint itself is
 * unchanged.
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
 *   4. a jscpd shim's sibling node_modules on PATH (e.g. a global npm install)
 * On WSL, PATH entries under /mnt/ are skipped — those are Windows installs
 * carrying the wrong platform's binary. If nothing resolves, callers fail open.
 *
 * Modes (mutually exclusive):
 *   (default)              print {"error", "clones": {...}} as JSON to stdout
 *   --baseline-out PATH    scan whole root, write baseline JSON to PATH
 *   --compare PATH         scan --touching files, print "BLOCK|n" / "OK|" / "OPEN|why"
 *   --where                print the resolved jscpd invocation, exit 1 if none
 *
 * Common flags: --root a,b  --min-tokens N  --touching ABS_PATH (repeatable)
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
        if (fs.existsSync(path.join(dir, "jscpd")) || fs.existsSync(path.join(dir, "jscpd.cmd"))) {
            pkgDirs.push(path.join(dir, "node_modules", "jscpd"));
        }
    }
    for (const pkgDir of pkgDirs) {
        const script = readPackageBinScript(pkgDir);
        if (script) return [process.execPath, script];
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
    // sha1 of the normalized code slice at absPath named by a jscpd entry.
    // Returns null when the slice cannot be read (missing file, bad offsets) so
    // the caller skips it rather than crash — a fingerprint we can't compute
    // must never masquerade as a match or a miss.
    let content;
    try {
        content = fs.readFileSync(absPath, "utf8");
    } catch (e) {
        return null;
    }
    const start = entry && entry.startLoc ? entry.startLoc.position : undefined;
    const end = entry && entry.endLoc ? entry.endLoc.position : undefined;
    if (typeof start !== "number" || typeof end !== "number" || end <= start) return null;
    const frag = normalize(content.slice(start, end));
    if (!frag) return null;
    return crypto.createHash("sha1").update(frag, "utf8").digest("hex");
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

function collect(roots, minTokens, touching) {
    // Returns {error, clones: {fp: {files: [...], pairs: N}}}. clones is
    // filtered to fingerprints involving a `touching` file when given, but each
    // entry always carries its FULL tree-wide file set and pair count so a
    // caller can compare like-for-like against a baseline.
    const repoRel = (abs) => path.relative(process.cwd(), abs).replace(/\\/g, "/");
    const rootsAbs = roots.map((r) => path.resolve(r));
    const touchingAbs = new Set((touching || []).map((t) => path.resolve(t)));

    let outDir;
    let report;
    try {
        outDir = fs.mkdtempSync(path.join(os.tmpdir(), "jscpd-"));
        report = runJscpd(rootsAbs, minTokens, outDir);
    } finally {
        if (outDir) fs.rmSync(outDir, { recursive: true, force: true });
    }
    if (report === null) return { error: "jscpd-unavailable", clones: {} };

    const clones = {}; // fp -> {files: Set, pairs: int}, tree-wide
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
        let fp = null;
        if (firstAbs) fp = sliceFingerprint(firstAbs, first);
        if (fp === null && secondAbs) fp = sliceFingerprint(secondAbs, second);
        if (fp === null) continue;
        const rec = clones[fp] || (clones[fp] = { files: new Set(), pairs: 0 });
        rec.pairs += 1;
        for (const abs of [firstAbs, secondAbs]) {
            if (!abs) continue;
            rec.files.add(repoRel(abs));
            if (touchingAbs.has(abs)) touchingFps.add(fp);
        }
    }

    const keys = touchingAbs.size ? touchingFps : Object.keys(clones);
    const out = {};
    for (const fp of keys) {
        out[fp] = { files: [...clones[fp].files].sort(), pairs: clones[fp].pairs };
    }
    return { error: null, clones: out };
}

function countNew(currentClones, baselineClones) {
    // How many of current's clones are NOT accounted for by the baseline.
    // New = a fingerprint the baseline never saw, OR a baselined fingerprint
    // that has spread to a file the baseline didn't list, OR one whose pair
    // count rose.
    let n = 0;
    for (const [fp, rec] of Object.entries(currentClones)) {
        const base = baselineClones[fp];
        if (!base) {
            n += 1;
        } else if ((rec.files || []).some((f) => !(base.files || []).includes(f))) {
            n += 1;
        } else if ((rec.pairs || 0) > (base.pairs || 0)) {
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
        baselineOut: null,
        noClobber: false,
        compare: null,
        where: false,
    };
    for (let i = 0; i < argv.length; i++) {
        switch (argv[i]) {
            case "--root": args.root = argv[++i]; break;
            case "--min-tokens": args.minTokens = parseInt(argv[++i], 10); break;
            case "--touching": args.touching.push(argv[++i]); break;
            case "--baseline-out": args.baselineOut = argv[++i]; break;
            case "--no-clobber": args.noClobber = true; break;
            case "--compare": args.compare = argv[++i]; break;
            case "--where": args.where = true; break;
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
        const argv = findJscpd();
        if (argv === null) return 1;
        process.stdout.write(argv.join(" ") + "\n");
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
            clones: result.clones,
        };
        // Atomic publish: an interrupted in-place truncate would leave a corrupt
        // baseline, and the hook would then fail open indefinitely. Write to a
        // temp file in the SAME directory, then publish. --no-clobber publishes
        // via link(2), which fails atomically if the target already exists — no
        // check-then-act window for two concurrent runs to clobber each other
        // (with a plain existence check as the fallback where hardlinks aren't
        // supported, e.g. some WSL drvfs mounts).
        const outAbs = path.resolve(args.baselineOut);
        // Random name + exclusive create ("wx" -> O_CREAT|O_EXCL): a predictable
        // temp path could be pre-planted as a symlink and writeFileSync would
        // happily follow it; O_EXCL refuses to open through any existing path.
        const tmp = path.join(
            path.dirname(outAbs),
            `.jscpd-baseline-${crypto.randomBytes(8).toString("hex")}.tmp`
        );
        try {
            fs.writeFileSync(tmp, JSON.stringify(sortKeysDeep(baseline), null, 2) + "\n", { flag: "wx" });
            if (args.noClobber) {
                try {
                    fs.linkSync(tmp, outAbs);
                } catch (e) {
                    if (e.code === "EEXIST") {
                        process.stderr.write(`refusing to overwrite existing ${args.baselineOut} (pass --force to regenerate)\n`);
                        return 1;
                    }
                    if (fs.existsSync(outAbs)) {
                        process.stderr.write(`refusing to overwrite existing ${args.baselineOut} (pass --force to regenerate)\n`);
                        return 1;
                    }
                    fs.renameSync(tmp, outAbs);
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
        const baselineClones = baseline.clones || {};
        const scanRoots = String(baseline.generatedFrom || args.root).split(",").map((r) => r.trim()).filter(Boolean);
        const minTokens = parseInt(baseline.minTokens, 10) || args.minTokens;
        const result = collect(scanRoots, minTokens, args.touching);
        if (result.error) {
            process.stdout.write(`OPEN|jscpd unavailable: ${result.error}\n`);
            return 0;
        }
        const fresh = countNew(result.clones, baselineClones);
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
