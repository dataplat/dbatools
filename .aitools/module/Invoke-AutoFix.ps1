function Invoke-AutoFix {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer and attempts to fix violations using AI coding tools.

    .DESCRIPTION
        This function runs PSScriptAnalyzer on files and creates targeted fix requests
        for any violations found. It supports batch processing of multiple files and
        can work with various input types including file paths, FileInfo objects, and
        command objects from Get-Command.

    .PARAMETER InputObject
        Array of objects that can be either file paths, FileInfo objects, or command objects (from Get-Command).
        If not specified, will process commands from the dbatools module.

    .PARAMETER First
        Specifies the maximum number of files to process.

    .PARAMETER Skip
        Specifies the number of files to skip before processing.

    .PARAMETER MaxFileSize
        The maximum size of files to process, in bytes. Files larger than this will be skipped.
        Defaults to 500kb.

    .PARAMETER PromptFilePath
        The path to the template file containing custom prompt structure for fixes.


    .PARAMETER PassCount
        Number of passes to run for each file. Sometimes multiple passes are needed.

    .PARAMETER AutoTest
        If specified, automatically runs tests after making changes.

    .PARAMETER FilePath
        The path to a single file that was modified by the AI tool (for backward compatibility).

    .PARAMETER SettingsPath
        Path to the PSScriptAnalyzer settings file.
        Defaults to "tests/PSScriptAnalyzerRules.psd1".

    .PARAMETER AiderParams
        The original AI tool parameters hashtable (for backward compatibility with single file mode).

    .PARAMETER MaxRetries
        Maximum number of retry attempts for fixing violations per file.

    .PARAMETER Model
        The AI model to use for fix attempts.

    .PARAMETER Tool
        The AI coding tool to use for fix attempts.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        This function supports both single-file mode (for backward compatibility) and
        batch processing mode with pipeline support.

    .EXAMPLE
        PS C:\> Invoke-AutoFix -FilePath "test.ps1" -SettingsPath "rules.psd1" -MaxRetries 3
        Fixes PSScriptAnalyzer violations in a single file (backward compatibility mode).

    .EXAMPLE
        PS C:\> Get-ChildItem "tests\*.Tests.ps1" | Invoke-AutoFix -First 10 -Tool Claude
        Processes the first 10 test files found, fixing PSScriptAnalyzer violations.

    .EXAMPLE
        PS C:\> Invoke-AutoFix -First 5 -Skip 10 -MaxFileSize 100kb -Tool Aider
        Processes 5 files starting from the 11th file, skipping files larger than 100kb.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipeline)]
        [PSObject[]]$InputObject,

        [int]$First = 10000,
        [int]$Skip = 0,
        [int]$MaxFileSize = 500kb,

        [string[]]$PromptFilePath,
        [string[]]$CacheFilePath = @(
            (Resolve-Path "$PSScriptRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path
        ),

        [int]$PassCount = 1,
        [switch]$AutoTest,

        # Backward compatibility parameters
        [string]$FilePath,
        [string]$SettingsPath = (Resolve-Path "$script:ModulePath/tests/PSScriptAnalyzerRules.psd1" -ErrorAction SilentlyContinue).Path,
        [hashtable]$AiderParams,

        [int]$MaxRetries = 0,
        [string]$Model,

        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',

        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    begin {
        # Import required modules
        if (-not (Get-Module dbatools.library -ListAvailable)) {
            Write-Warning "dbatools.library not found, installing"
            Install-Module dbatools.library -Scope CurrentUser -Force
        }

        # Show fake progress bar during slow dbatools import, pass some time
        Write-Progress -Activity "Loading dbatools Module" -Status "Initializing..." -PercentComplete 0
        Start-Sleep -Milliseconds 100
        Write-Progress -Activity "Loading dbatools Module" -Status "Loading core functions..." -PercentComplete 20
        Start-Sleep -Milliseconds 200
        Write-Progress -Activity "Loading dbatools Module" -Status "Populating RepositorySourceLocation..." -PercentComplete 40
        Start-Sleep -Milliseconds 300
        Write-Progress -Activity "Loading dbatools Module" -Status "Loading database connections..." -PercentComplete 60
        Start-Sleep -Milliseconds 200
        Write-Progress -Activity "Loading dbatools Module" -Status "Finalizing module load..." -PercentComplete 80
        Start-Sleep -Milliseconds 100
        Write-Progress -Activity "Loading dbatools Module" -Status "Importing module..." -PercentComplete 90
        Import-Module $script:ModulePath/dbatools.psm1 -Force
        Write-Progress -Activity "Loading dbatools Module" -Status "Complete" -PercentComplete 100
        Start-Sleep -Milliseconds 100
        Write-Progress -Activity "Loading dbatools Module" -Completed

        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
        $commandsToProcess = @()

        # Validate tool-specific parameters
        if ($Tool -eq 'Claude') {
            # Warn about Aider-only parameters when using Claude
            if ($PSBoundParameters.ContainsKey('CachePrompts')) {
                Write-Warning "CachePrompts parameter is Aider-specific and will be ignored when using Claude Code"
            }
            if ($PSBoundParameters.ContainsKey('NoStream')) {
                Write-Warning "NoStream parameter is Aider-specific and will be ignored when using Claude Code"
            }
            if ($PSBoundParameters.ContainsKey('YesAlways')) {
                Write-Warning "YesAlways parameter is Aider-specific and will be ignored when using Claude Code"
            }
        }

        # Handle backward compatibility - single file mode
        if ($FilePath -and $AiderParams) {
            Write-Verbose "Running in backward compatibility mode for single file: $FilePath"

            $invokeParams = @{
                FilePath     = $FilePath
                SettingsPath = $SettingsPath
                AiderParams  = $AiderParams
                MaxRetries   = $MaxRetries
                Model        = $Model
                Tool         = $Tool
            }
            if ($ReasoningEffort) {
                $invokeParams.ReasoningEffort = $ReasoningEffort
            }

            Invoke-AutoFixSingleFile @invokeParams
        }
    }

    process {
        if ($InputObject) {
            foreach ($item in $InputObject) {
                Write-Verbose "Processing input object of type: $($item.GetType().FullName)"

                if ($item -is [System.Management.Automation.CommandInfo]) {
                    $commandsToProcess += $item
                } elseif ($item -is [System.IO.FileInfo]) {
                    $path = (Resolve-Path $item.FullName).Path
                    Write-Verbose "Processing FileInfo path: $path"
                    if (Test-Path $path) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($path) -replace '\.Tests$', ''
                        Write-Verbose "Extracted command name: $cmdName"
                        $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
                        if ($cmd) {
                            $commandsToProcess += $cmd
                        } else {
                            Write-Warning "Could not find command for test file: $path"
                        }
                    }
                } elseif ($item -is [string]) {
                    Write-Verbose "Processing string path: $item"
                    try {
                        $resolvedItem = (Resolve-Path $item).Path
                        if (Test-Path $resolvedItem) {
                            $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedItem) -replace '\.Tests$', ''
                            Write-Verbose "Extracted command name: $cmdName"
                            $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
                            if ($cmd) {
                                $commandsToProcess += $cmd
                            } else {
                                Write-Warning "Could not find command for test file: $resolvedItem"
                            }
                        } else {
                            Write-Warning "File not found: $resolvedItem"
                        }
                    } catch {
                        Write-Warning "Could not resolve path: $item"
                    }
                } else {
                    Write-Warning "Unsupported input type: $($item.GetType().FullName)"
                }
            }
        }
    }

    end {
        # Only get all commands if no InputObject was provided at all (user called with no params)
        if (-not $commandsToProcess -and -not $PSBoundParameters.ContainsKey('InputObject') -and -not $FilePath) {
            Write-Verbose "No input objects provided, getting commands from dbatools module"
            $commandsToProcess = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
        } elseif (-not $commandsToProcess) {
            Write-Warning "No valid commands found to process from provided input"
            return
        }

        # Get total count for progress tracking
        $totalCommands = $commandsToProcess.Count
        $currentCommand = 0

        # Initialize progress
        Write-Progress -Activity "Running AutoFix" -Status "Starting PSScriptAnalyzer fixes..." -PercentComplete 0

        foreach ($command in $commandsToProcess) {
            $currentCommand++
            $cmdName = $command.Name

            # Update progress at START of iteration
            $percentComplete = [math]::Round(($currentCommand / $totalCommands) * 100, 2)
            Write-Progress -Activity "Running AutoFix" -Status "Fixing $cmdName ($currentCommand of $totalCommands)" -PercentComplete $percentComplete
            $filename = (Resolve-Path "$script:ModulePath/tests/$cmdName.Tests.ps1" -ErrorAction SilentlyContinue).Path

            # Show progress for every file being processed
            Write-Progress -Activity "Running AutoFix with $Tool" -Status "Scanning $cmdName ($currentCommand/$totalCommands)" -PercentComplete (($currentCommand / $totalCommands) * 100)

            Write-Verbose "Processing command: $cmdName"
            Write-Verbose "Test file path: $filename"

            if (-not $filename -or -not (Test-Path $filename)) {
                Write-Verbose "No tests found for $cmdName, file not found"
                continue
            }

            # if file is larger than MaxFileSize, skip
            if ((Get-Item $filename).Length -gt $MaxFileSize) {
                Write-Warning "Skipping $cmdName because it's too large"
                continue
            }

            if ($PSCmdlet.ShouldProcess($filename, "Run PSScriptAnalyzer fixes using $Tool")) {
                for ($pass = 1; $pass -le $PassCount; $pass++) {
                    if ($PassCount -gt 1) {
                        # Nested progress for multiple passes
                        Write-Progress -Id 1 -ParentId 0 -Activity "Pass $pass of $PassCount" -Status "Processing $cmdName" -PercentComplete (($pass / $PassCount) * 100)
                    }

                    # Run the fix process
                    $invokeParams = @{
                        FilePath     = $filename
                        SettingsPath = $SettingsPath
                        MaxRetries   = $MaxRetries
                        Model        = $Model
                        Tool         = $Tool
                        AutoTest     = $AutoTest
                        Verbose      = $false
                    }
                    if ($ReasoningEffort) {
                        $invokeParams.ReasoningEffort = $ReasoningEffort
                    }

                    Invoke-AutoFixProcess @invokeParams
                }

                # Clear nested progress if used
                if ($PassCount -gt 1) {
                    Write-Progress -Id 1 -Activity "Passes Complete" -Completed
                }
            }
        }

        # Clear main progress bar
        Write-Progress -Activity "Running AutoFix" -Status "Complete" -Completed
    }
}