#!/bin/bash
# stop-registration-check.sh - Verify new public/*.ps1 commands are registered.
# New dbatools commands must appear in BOTH dbatools.psd1 AND dbatools.psm1.

source "$(dirname "$0")/lib-stop-guard.sh"
if [[ "$STOP_GUARD_SKIP" == "true" ]]; then
    exit 0
fi

python3 << 'PY'
import subprocess, sys, os, json

try:
    diff = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], text=True, stderr=subprocess.DEVNULL)
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], text=True, stderr=subprocess.DEVNULL)
except subprocess.CalledProcessError:
    sys.exit(0)

new_public = list(set(
    f for f in (diff + untracked).splitlines()
    if f.startswith('public/') and f.endswith('.ps1')
))

if not new_public:
    sys.exit(0)

violations = []
try:
    psd1 = open('dbatools.psd1').read()
except OSError:
    psd1 = ""
try:
    psm1 = open('dbatools.psm1').read()
except OSError:
    psm1 = ""

for filepath in sorted(new_public):
    func = os.path.splitext(os.path.basename(filepath))[0]
    if f"'{func}'" not in psd1 and f'"{func}"' not in psd1:
        violations.append(f"  {func}: missing from dbatools.psd1 FunctionsToExport")
    if func not in psm1:
        violations.append(f"  {func}: missing from dbatools.psm1 Export-ModuleMember")

if not violations:
    sys.exit(0)

msg = (
    "REGISTRATION INCOMPLETE: New command(s) in public/ not registered in manifest.\n\n"
    "Every new dbatools command must appear in TWO places:\n"
    "  1. dbatools.psd1  — FunctionsToExport array\n"
    "  2. dbatools.psm1  — Export-ModuleMember section\n\n"
    + "\n".join(violations)
    + "\n\nFix both files before finishing."
)
sys.stdout.write(json.dumps({"decision": "block", "reason": msg}) + "\n")
PY
