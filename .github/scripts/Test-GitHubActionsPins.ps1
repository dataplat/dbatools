[CmdletBinding()]
param(
    [string]$WorkflowPath = ".github/workflows"
)

$ErrorActionPreference = "Stop"

$resolvedWorkflowPath = Resolve-Path -LiteralPath $WorkflowPath
$workflowFiles = Get-ChildItem -LiteralPath $resolvedWorkflowPath -Recurse -File |
    Where-Object { $PSItem.Extension -in ".yml", ".yaml" }

if (-not $workflowFiles) {
    throw "No GitHub Actions workflow files found under $WorkflowPath"
}

$unpinnedActions = foreach ($file in $workflowFiles) {
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++

        if ($line -match '^\s*#') {
            continue
        }

        if ($line -notmatch '^\s*(?:-\s*)?uses:\s*(?<Action>[^#\s]+)') {
            continue
        }

        $action = $Matches.Action.Trim("'`"")

        if ($action -match '^\./|^\.\\|^docker://') {
            continue
        }

        $refSeparator = $action.LastIndexOf("@")
        if ($refSeparator -lt 0) {
            [pscustomobject]@{
                File   = Resolve-Path -LiteralPath $file.FullName -Relative
                Line   = $lineNumber
                Uses   = $action
                Reason = "missing @ref"
            }
            continue
        }

        $ref = $action.Substring($refSeparator + 1)
        if ($ref -notmatch '^[0-9a-fA-F]{40}$') {
            [pscustomobject]@{
                File   = Resolve-Path -LiteralPath $file.FullName -Relative
                Line   = $lineNumber
                Uses   = $action
                Reason = "ref is not a full 40-character commit SHA"
            }
        }
    }
}

if ($unpinnedActions) {
    $unpinnedActions | Format-Table -AutoSize | Out-String | Write-Error
    throw "GitHub Actions must be pinned to full commit SHAs."
}

Write-Host "All GitHub Actions references are pinned to full commit SHAs."
