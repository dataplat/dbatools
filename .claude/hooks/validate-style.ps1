#!/usr/bin/env pwsh
# PreToolUse hook: Consolidated style validation for dbatools
# Runs all style checks in a single PowerShell process for performance
# Launched by pre-write-style.sh, which picks pwsh or powershell.exe —
# this script must stay Windows PowerShell 5.1 compatible.

$ErrorActionPreference = "Stop"

try {
    $inputJson = $input | Out-String | ConvertFrom-Json
} catch {
    exit 0
}

$toolInput = $inputJson.tool_input
$filePath = $toolInput.file_path
if (-not $filePath) { exit 0 }
if ($filePath -notlike "*.ps1") { exit 0 }

$content = if ($toolInput.new_string) { $toolInput.new_string } else { $toolInput.content }
if (-not $content) { exit 0 }

$violations = @()
$lines = $content -split "`n"

# Track state for multi-line constructs
$inHereStringSingle = $false
$inHereStringDouble = $false
$inHashtable = $false
$hashtableLines = @()
$hashtableStart = 0
$misalignedHashtables = @()

# Patterns (using double quotes with escaping)
$patternComment = "^\s*#"
$patternHereStringSingleStart = "@'"
$patternHereStringDoubleStart = "@`""
$patternHereStringSingleEnd = "^'@"
$patternHereStringDoubleEnd = "^`"@"
$patternBacktick = "``\s*$"
$patternBoolAttribute = "\[\s*(Parameter|CmdletBinding|OutputType|ValidateSet)\s*\([^]]*=\s*\`$(true|false)"
$patternStaticNew = "::new\s*\("
$patternSingleQuote = "(?<![@])'.+'"
$patternPlainSplat = "\`$splat\s*="
$patternNamedSplat = "\`$splat[A-Z][a-zA-Z0-9]*\s*="
$patternArrayList = "ArrayList"
$patternGenericList = "Generic\.List"
$patternStandaloneBrace = "^\s*\{\s*$"
$patternPrevLineEnd = "\)\s*$"
$patternControlKeyword = "(if|else|elseif|foreach|for|while|switch|try|catch|finally)\s*$"
$patternHashtableStart = "@\{"
$patternHashtableEnd = "^\s*\}"
$patternTrailingSpace = "\s+$"

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].TrimEnd("`r")
    $lineNum = $i + 1
    $isComment = $line -match $patternComment

    # Track here-string state
    if ($line -match $patternHereStringSingleStart) { $inHereStringSingle = $true }
    if ($line -match $patternHereStringDoubleStart) { $inHereStringDouble = $true }
    if ($line -match $patternHereStringSingleEnd) { $inHereStringSingle = $false; continue }
    if ($line -match $patternHereStringDoubleEnd) { $inHereStringDouble = $false; continue }
    if ($inHereStringSingle -or $inHereStringDouble) { continue }

    # Skip comments for most checks
    if (-not $isComment) {
        # 1. No backticks for line continuation
        if ($line -match $patternBacktick) {
            $violations += "Line ${lineNum}: Backtick line continuation. Use splatting instead."
        }

        # 2. No = $true in parameter attributes
        if ($line -match $patternBoolAttribute) {
            $violations += "Line ${lineNum}: Use [Parameter(Mandatory)] not = `$true syntax."
        }

        # 3. No static new method (PowerShell v3 compatibility)
        if ($line -match $patternStaticNew) {
            $violations += "Line ${lineNum}: Use New-Object for PS v3 compatibility."
        }

        # 4. No single quotes (except here-strings already handled above)
        if ($line -match $patternSingleQuote) {
            $violations += "Line ${lineNum}: Use double quotes instead of single quotes."
        }

        # 5. No plain $splat variable names
        if ($line -match $patternPlainSplat -and $line -notmatch $patternNamedSplat) {
            $violations += "Line ${lineNum}: Use `$splat<Purpose> naming (e.g., `$splatConnection)."
        }

        # 6. No ArrayList or Generic.List collection
        if ($line -match $patternArrayList) {
            $violations += "Line ${lineNum}: Output directly to pipeline, not ArrayList."
        }
        if ($line -match $patternGenericList) {
            $violations += "Line ${lineNum}: Output directly to pipeline, not Generic.List."
        }

        # 7. OTBS - no standalone opening brace (Allman style)
        if ($line -match $patternStandaloneBrace -and $i -gt 0) {
            $prevLine = $lines[$i - 1].TrimEnd("`r")
            if ($prevLine -match $patternPrevLineEnd -or $prevLine -match $patternControlKeyword) {
                $violations += "Line ${lineNum}: Use OTBS - opening brace on same line as statement."
            }
        }

        # 8. Track hashtables for alignment check
        if ($line -match $patternHashtableStart) {
            $inHashtable = $true
            $hashtableLines = @()
            $hashtableStart = $lineNum
            # Don't add this line to hashtableLines - it's the opening, not an entry
        } elseif ($inHashtable) {
            if ($line -match $patternHashtableEnd) {
                if ($hashtableLines.Count -ge 2) {
                    $equalsPositions = $hashtableLines | ForEach-Object {
                        $pos = $_.IndexOf("=")
                        if ($pos -ge 0) { $pos }
                    } | Where-Object { $null -ne $_ } | Select-Object -Unique
                    if ($equalsPositions.Count -gt 1) {
                        $misalignedHashtables += "Lines $hashtableStart-$lineNum"
                    }
                }
                $inHashtable = $false
            } elseif ($line -match "=" -and $line.Trim() -ne "") {
                $hashtableLines += $line
            }
        }
    }

    # 9. No trailing spaces (check even in comments)
    if ($line -match $patternTrailingSpace) {
        $violations += "Line ${lineNum}: Trailing whitespace."
    }
}

# Add hashtable alignment violations
foreach ($ht in $misalignedHashtables) {
    $violations += "${ht}: Hashtable = signs must be vertically aligned."
}

if ($violations.Count -gt 0) {
    $summary = ($violations | Select-Object -First 5) -join "`n"
    $more = if ($violations.Count -gt 5) { "`n... and $($violations.Count - 5) more violations" } else { "" }
    [Console]::Error.WriteLine("BLOCKED: dbatools style violations:`n$summary$more")
    exit 2
}

exit 0
