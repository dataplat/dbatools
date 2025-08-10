function Invoke-AutoFixProcess {
    <#
    .SYNOPSIS
        Core processing logic for AutoFix operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$SettingsPath,

        [Parameter(Mandatory)]
        [int]$MaxRetries,

        [string]$Model,

        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',

        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort,

        [switch]$AutoTest
    )

    $attempt = 0
    $maxTries = if ($MaxRetries -eq 0) { 1 } else { $MaxRetries + 1 }

    # Initialize progress
    Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Starting..." -PercentComplete 0

    while ($attempt -lt $maxTries) {
        $attempt++
        $isRetry = $attempt -gt 1

        # Update progress for each attempt
        $percentComplete = if ($maxTries -gt 1) { [math]::Round(($attempt / $maxTries) * 100, 2) } else { 50 }
        Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "$(if($isRetry){'Retry '}else{''})Attempt $attempt$(if($maxTries -gt 1){' of ' + $maxTries}else{''}) - Running PSScriptAnalyzer" -PercentComplete $percentComplete

        Write-Verbose "Running PSScriptAnalyzer on $FilePath (attempt $attempt$(if($maxTries -gt 1){'/'+$maxTries}else{''}))"

        try {
            # Get file content hash before potential changes
            $fileContentBefore = if ($isRetry -and (Test-Path $FilePath)) {
                Get-FileHash $FilePath -Algorithm MD5 | Select-Object -ExpandProperty Hash
            } else { $null }

            # Run PSScriptAnalyzer with the specified settings
            $scriptAnalyzerParams = @{
                Path        = $FilePath
                Settings    = $SettingsPath
                ErrorAction = "Stop"
            }

            $analysisResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams
            $currentViolationCount = if ($analysisResults) { $analysisResults.Count } else { 0 }

            if ($currentViolationCount -eq 0) {
                Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "No violations found - Complete" -PercentComplete 100
                Write-Verbose "No PSScriptAnalyzer violations found for $(Split-Path $FilePath -Leaf)"
                break
            }

            # If this is a retry and we have no retries allowed, exit
            if ($isRetry -and $MaxRetries -eq 0) {
                Write-Verbose "MaxRetries is 0, not attempting fixes after initial run"
                break
            }

            # Store previous violation count for comparison on retries
            if (-not $isRetry) {
                $script:previousViolationCount = $currentViolationCount
            }

            # Update status when sending to AI
            Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Sending fix request to $Tool (Attempt $attempt)" -PercentComplete $percentComplete

            Write-Verbose "Found $currentViolationCount PSScriptAnalyzer violation(s)"

            # Format violations into a focused fix message
            $fixMessage = "The following are PSScriptAnalyzer violations that need to be fixed:`n`n"

            foreach ($result in $analysisResults) {
                $fixMessage += "Rule: $($result.RuleName)`n"
                $fixMessage += "Line: $($result.Line)`n"
                $fixMessage += "Message: $($result.Message)`n`n"
            }

            $fixMessage += "CONSIDER THIS WITH PESTER CONTEXTS AND SCOPES WHEN DECIDING IF SCRIPT ANALYZER IS RIGHT."

            Write-Verbose "Sending focused fix request to $Tool"

            # Build AI tool parameters
            $aiParams = @{
                Message  = $fixMessage
                File     = $FilePath
                Model    = $Model
                Tool     = $Tool
                AutoTest = $AutoTest
            }

            if ($ReasoningEffort) {
                $aiParams.ReasoningEffort = $ReasoningEffort
            } elseif ($Tool -eq 'Aider') {
                # Set default for Aider to prevent validation errors
                $aiParams.ReasoningEffort = 'medium'
            }

            # Add tool-specific parameters - no context files for focused AutoFix
            if ($Tool -eq 'Aider') {
                $aiParams.YesAlways = $true
                $aiParams.NoStream = $true
                $aiParams.CachePrompts = $true
                # Don't add ReadFile for AutoFix - keep it focused
            }
            # For Claude Code - don't add ContextFiles for AutoFix - keep it focused

            # Invoke the AI tool with the focused fix message
            Invoke-AITool @aiParams

            # Run Invoke-DbatoolsFormatter after AI tool execution in AutoFix
            if (Test-Path $FilePath) {
                Write-Verbose "Running Invoke-DbatoolsFormatter on $FilePath in AutoFix"
                try {
                    Invoke-DbatoolsFormatter -Path $FilePath
                } catch {
                    Write-Warning "Invoke-DbatoolsFormatter failed for $FilePath in AutoFix: $($_.Exception.Message)"
                }
            }

            # Add explicit file sync delay to ensure disk writes complete
            Start-Sleep -Milliseconds 500

            # For retries, check if file actually changed
            if ($isRetry) {
                $fileContentAfter = if (Test-Path $FilePath) {
                    Get-FileHash $FilePath -Algorithm MD5 | Select-Object -ExpandProperty Hash
                } else { $null }

                if ($fileContentBefore -and $fileContentAfter -and $fileContentBefore -eq $fileContentAfter) {
                    Write-Verbose "File content unchanged after AI tool execution, stopping retries"
                    break
                }

                # Check if we made progress (reduced violations)
                if ($currentViolationCount -ge $script:previousViolationCount) {
                    Write-Verbose "No progress made (violations: $script:previousViolationCount -> $currentViolationCount), stopping retries"
                    break
                }

                $script:previousViolationCount = $currentViolationCount
            }

        } catch {
            Write-Warning "Failed to run PSScriptAnalyzer on $FilePath`: $($_.Exception.Message)"
            break
        }
    }

    # Clear progress
    Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Complete" -Completed

    if ($attempt -eq $maxTries -and $MaxRetries -gt 0) {
        Write-Warning "AutoFix reached maximum retry limit ($MaxRetries) for $FilePath"
    }
}