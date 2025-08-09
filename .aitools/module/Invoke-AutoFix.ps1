function Invoke-AutoFix {
    <#
    .SYNOPSIS
        Automatically fixes PSScriptAnalyzer violations using AI tools.

    .DESCRIPTION
        This function runs PSScriptAnalyzer on specified files and uses AI tools to automatically fix
        any violations found. It can retry multiple times and works with both Aider and Claude Code.

    .PARAMETER FilePath
        The path to the file(s) to analyze and fix.

    .PARAMETER SettingsPath
        Path to the PSScriptAnalyzer settings file.
        Defaults to the dbatools PSScriptAnalyzerRules.psd1 file.

    .PARAMETER AiderParams
        Parameters to pass to the AI tool for fixing violations.

    .PARAMETER MaxRetries
        Maximum number of retry attempts when violations are found.
        Defaults to 3.

    .PARAMETER Model
        The AI model to use for fixing violations.

    .PARAMETER Tool
        The AI coding tool to use for fixes.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        Tags: CodeQuality, PSScriptAnalyzer, Automation
        Author: dbatools team

    .EXAMPLE
        PS C:/> Invoke-AutoFix -FilePath "C:/test.ps1"
        Analyzes the file and fixes any PSScriptAnalyzer violations using default settings.

    .EXAMPLE
        PS C:/> Invoke-AutoFix -FilePath "C:/test.ps1" -MaxRetries 5 -Tool Aider
        Analyzes and fixes violations with up to 5 retry attempts using Aider.

    .EXAMPLE
        PS C:/> Invoke-AutoFix -FilePath @("file1.ps1", "file2.ps1") -SettingsPath "custom-rules.psd1"
        Fixes multiple files using custom PSScriptAnalyzer rules.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$FilePath,
        [string]$SettingsPath,
        [hashtable]$AiderParams = @{},
        [int]$MaxRetries = 3,
        [string]$Model,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-Verbose "Starting AutoFix for $($FilePath.Count) file(s)"

    # Validate PSScriptAnalyzer is available
    if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
        Write-Warning "PSScriptAnalyzer module not found. Installing..."
        try {
            Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
        } catch {
            Write-Error "Failed to install PSScriptAnalyzer: $_"
            return
        }
    }

    # Import PSScriptAnalyzer if not already loaded
    if (-not (Get-Module PSScriptAnalyzer)) {
        Import-Module PSScriptAnalyzer
    }

    foreach ($file in $FilePath) {
        if (-not (Test-Path $file)) {
            Write-Warning "File not found: $file"
            continue
        }

        Write-Verbose "Processing file: $file"
        $retryCount = 0
        $hasViolations = $true

        while ($hasViolations -and $retryCount -lt $MaxRetries) {
            $retryCount++
            Write-Verbose "AutoFix attempt $retryCount of $MaxRetries for $file"

            # Run PSScriptAnalyzer
            $analyzerParams = @{
                Path = $file
            }

            if ($SettingsPath -and (Test-Path $SettingsPath)) {
                $analyzerParams.Settings = $SettingsPath
            }

            try {
                $violations = Invoke-ScriptAnalyzer @analyzerParams
            } catch {
                Write-Error "Failed to run PSScriptAnalyzer on $file`: $_"
                break
            }

            if (-not $violations) {
                Write-Verbose "No violations found in $file"
                $hasViolations = $false
                break
            }

            Write-Verbose "Found $($violations.Count) violation(s) in $file"

            # Group violations by severity for better reporting
            $violationSummary = $violations | Group-Object Severity | ForEach-Object {
                "$($_.Count) $($_.Name)"
            }
            Write-Verbose "Violation summary: $($violationSummary -join ', ')"

            # Create fix message for AI tool
            $violationDetails = $violations | ForEach-Object {
                "Line $($_.Line): $($_.RuleName) - $($_.Message)"
            }

            $fixMessage = @"
Please fix the following PSScriptAnalyzer violations in this PowerShell file:

$($violationDetails -join "`n")

Focus on:
1. Following PowerShell best practices
2. Proper parameter validation
3. Consistent code formatting
4. Removing any deprecated syntax
5. Ensuring cross-platform compatibility

Make minimal changes to preserve functionality while fixing the violations.
"@

            # Prepare AI tool parameters
            $aiParams = @{
                Message = $fixMessage
                File = @($file)
                Tool = $Tool
            }

            if ($Model) {
                $aiParams.Model = $Model
            }

            if ($PSBoundParameters.ContainsKey('ReasoningEffort')) {
                $aiParams.ReasoningEffort = $ReasoningEffort
            }

            # Merge with any additional parameters
            foreach ($key in $AiderParams.Keys) {
                if ($key -notin $aiParams.Keys) {
                    $aiParams[$key] = $AiderParams[$key]
                }
            }

            Write-Verbose "Invoking $Tool to fix violations (attempt $retryCount)"

            try {
                Invoke-AITool @aiParams
            } catch {
                Write-Error "Failed to invoke $Tool for fixing violations: $_"
                break
            }

            # Brief pause to allow file system to settle
            Start-Sleep -Milliseconds 500
        }

        if ($hasViolations -and $retryCount -ge $MaxRetries) {
            Write-Warning "Maximum retry attempts ($MaxRetries) reached for $file. Some violations may remain."

            # Final check to report remaining violations
            try {
                $analyzerParams = @{
                    Path = $file
                }

                if ($SettingsPath -and (Test-Path $SettingsPath)) {
                    $analyzerParams.Settings = $SettingsPath
                }

                $remainingViolations = Invoke-ScriptAnalyzer @analyzerParams
                if ($remainingViolations) {
                    Write-Warning "Remaining violations in $file`:"
                    $remainingViolations | ForEach-Object {
                        Write-Warning "  Line $($_.Line): $($_.RuleName) - $($_.Message)"
                    }
                }
            } catch {
                Write-Warning "Could not perform final violation check on $file"
            }
        } elseif (-not $hasViolations) {
            Write-Verbose "Successfully fixed all violations in $file after $retryCount attempt(s)"
        }
    }

    Write-Verbose "AutoFix completed for all files"
}