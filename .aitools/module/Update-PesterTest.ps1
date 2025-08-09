function Update-PesterTest {
    <#
    .SYNOPSIS
        Updates Pester tests to v5 format for dbatools commands.

    .DESCRIPTION
        Updates existing Pester tests to v5 format for dbatools commands. This function processes test files
        and converts them to use the newer Pester v5 parameter validation syntax. It skips files that have
        already been converted or exceed the specified size limit.

    .PARAMETER InputObject
        Array of objects that can be either file paths, FileInfo objects, or command objects (from Get-Command).
        If not specified, will process commands from the dbatools module.

    .PARAMETER First
        Specifies the maximum number of commands to process.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing.

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to "$PSScriptRoot/../aitools/prompts/template.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.

    .PARAMETER MaxFileSize
        The maximum size of test files to process, in bytes. Files larger than this will be skipped.
        Defaults to 7.5kb.

    .PARAMETER Model
        The AI model to use (e.g., azure/gpt-4o, gpt-4o-mini, claude-3-5-sonnet for Aider; claude-sonnet-4-20250514 for Claude Code).

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER AutoTest
        If specified, automatically runs tests after making changes.

    .PARAMETER PassCount
        Sometimes you need multiple passes to get the desired result.

    .PARAMETER NoAuthFix
        If specified, disables automatic PSScriptAnalyzer fixes after AI modifications.
        By default, autofix is enabled and runs separately from PassCount iterations using targeted fix messages.

    .PARAMETER AutoFixModel
        The AI model to use for AutoFix operations. Defaults to the same model as specified in -Model.
        If not specified, it will use the same model as the main operation.

    .PARAMETER MaxRetries
        Maximum number of retry attempts when AutoFix finds PSScriptAnalyzer violations.
        Only applies when -AutoFix is specified. Defaults to 3.

    .PARAMETER SettingsPath
        Path to the PSScriptAnalyzer settings file used by AutoFix.
        Defaults to "$PSScriptRoot/../tests/PSScriptAnalyzerRules.psd1".

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        Tags: Testing, Pester
        Author: dbatools team

    .EXAMPLE
        PS C:/> Update-PesterTest
        Updates all eligible Pester tests to v5 format using default parameters with Claude Code.

    .EXAMPLE
        PS C:/> Update-PesterTest -Tool Aider -First 10 -Skip 5
        Updates 10 test files starting from the 6th command, skipping the first 5, using Aider.

    .EXAMPLE
        PS C:/> "C:/tests/Get-DbaDatabase.Tests.ps1", "C:/tests/Get-DbaBackup.Tests.ps1" | Update-PesterTest -Tool Claude
        Updates the specified test files to v5 format using Claude Code.

    .EXAMPLE
        PS C:/> Get-Command -Module dbatools -Name "*Database*" | Update-PesterTest -Tool Aider
        Updates test files for all commands in dbatools module that match "*Database*" using Aider.

    .EXAMPLE
        PS C:/> Get-ChildItem ./tests/Add-DbaRegServer.Tests.ps1 | Update-PesterTest -Verbose -Tool Claude
        Updates the specific test file from a Get-ChildItem result using Claude Code.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias('FullName', 'Path')]
        [PSObject[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = @((Resolve-Path "$PSScriptRoot/prompts/prompt.md" -ErrorAction SilentlyContinue).Path),
        [string[]]$CacheFilePath = @(
            (Resolve-Path "$PSScriptRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$script:ModulePath/private/testing/Get-TestConfig.ps1" -ErrorAction SilentlyContinue).Path
        ),
        [int]$MaxFileSize = 500kb,
        [string]$Model,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [switch]$AutoTest,
        [int]$PassCount = 1,
        [switch]$NoAuthFix,
        [string]$AutoFixModel = $Model,
        [int]$MaxRetries = 0,
        [string]$SettingsPath = (Resolve-Path "$script:ModulePath/tests/PSScriptAnalyzerRules.psd1" -ErrorAction SilentlyContinue).Path,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )
    begin {
        # Full prompt path
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

        $promptTemplate = if ($PromptFilePath[0] -and (Test-Path $PromptFilePath[0])) {
            Get-Content $PromptFilePath[0]
        } else {
            @("Template not found at $($PromptFilePath[0])")
        }
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
    }

    process {
        if ($InputObject) {
            foreach ($item in $InputObject) {
                Write-Verbose "Processing input object of type: $($item.GetType().FullName)"

                if ($item -is [System.Management.Automation.CommandInfo]) {
                    $commandsToProcess += $item
                } elseif ($item -is [System.IO.FileInfo]) {
                    # For FileInfo objects, use the file directly if it's a test file
                    $path = $item.FullName
                    Write-Verbose "Processing FileInfo path: $path"
                    if ($path -like "*.Tests.ps1" -and (Test-Path $path)) {
                        # Create a mock command object for the test file
                        $testFileCommand = [PSCustomObject]@{
                            Name = [System.IO.Path]::GetFileNameWithoutExtension($path) -replace '\.Tests$', ''
                            TestFilePath = $path
                            IsTestFile = $true
                        }
                        $commandsToProcess += $testFileCommand
                    } else {
                        Write-Warning "FileInfo object is not a valid test file: $path"
                        return # Stop processing on invalid input
                    }
                } elseif ($item -is [string]) {
                    Write-Verbose "Processing string path: $item"
                    try {
                        $resolvedItem = (Resolve-Path $item -ErrorAction Stop).Path
                        if ($resolvedItem -like "*.Tests.ps1" -and (Test-Path $resolvedItem)) {
                            $testFileCommand = [PSCustomObject]@{
                                Name = [System.IO.Path]::GetFileNameWithoutExtension($resolvedItem) -replace '\.Tests$', ''
                                TestFilePath = $resolvedItem
                                IsTestFile = $true
                            }
                            $commandsToProcess += $testFileCommand
                        } else {
                            Write-Warning "String path is not a valid test file: $resolvedItem"
                            return # Stop processing on invalid input
                        }
                    } catch {
                        Write-Warning "Could not resolve path: $item"
                        return # Stop processing on failed resolution
                    }
                } else {
                    Write-Warning "Unsupported input type: $($item.GetType().FullName)"
                    return # Stop processing on unsupported type
                }
            }
        }
    }

    end {
        # Only get all commands if no InputObject was provided at all (user called with no params)
        if (-not $commandsToProcess -and -not $PSBoundParameters.ContainsKey('InputObject')) {
            Write-Verbose "No input objects provided, getting commands from dbatools module"
            $commandsToProcess = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
        } elseif (-not $commandsToProcess) {
            Write-Warning "No valid commands found to process from provided input"
            return
        }

        # Get total count for progress tracking
        $totalCommands = $commandsToProcess.Count
        $currentCommand = 0

        foreach ($command in $commandsToProcess) {
            $currentCommand++

            if ($command.IsTestFile) {
                # Handle direct test file input
                $cmdName = $command.Name
                $filename = $command.TestFilePath
            } else {
                # Handle command object input
                $cmdName = $command.Name
                $filename = (Resolve-Path "$script:ModulePath/tests/$cmdName.Tests.ps1" -ErrorAction SilentlyContinue).Path
            }

            Write-Verbose "Processing command: $cmdName"
            Write-Verbose "Test file path: $filename"

            if (-not $filename -or -not (Test-Path $filename)) {
                Write-Warning "No tests found for $cmdName, file not found"
                continue
            }

            # if file is larger than MaxFileSize, skip
            if ((Get-Item $filename).Length -gt $MaxFileSize) {
                Write-Warning "Skipping $cmdName because it's too large"
                continue
            }

            $parameters = $command.Parameters.Values | Where-Object Name -notin $commonParameters
            $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $cmdName
            $cmdPrompt = $cmdPrompt -replace "--PARMZ--", ($parameters.Name -join "`n")
            $cmdprompt = $cmdPrompt -join "`n"

            if ($PSCmdlet.ShouldProcess($filename, "Update Pester test to v5 format and/or style using $Tool")) {
                # Separate directories from files in CacheFilePath
                $cacheDirectories = @()
                $cacheFiles = @()

                foreach ($cachePath in $CacheFilePath) {
                    Write-Verbose "Examining cache path: $cachePath"
                    if ($cachePath -and (Test-Path $cachePath -PathType Container)) {
                        Write-Verbose "Found directory: $cachePath"
                        $cacheDirectories += $cachePath
                    } elseif ($cachePath -and (Test-Path $cachePath -PathType Leaf)) {
                        Write-Verbose "Found file: $cachePath"
                        $cacheFiles += $cachePath
                    } else {
                        Write-Warning "Cache path not found or inaccessible: $cachePath"
                    }
                }

                if ($cacheDirectories.Count -gt 0) {
                    Write-Verbose "CacheFilePath contains $($cacheDirectories.Count) directories, expanding to files"
                    Write-Verbose "Also using $($cacheFiles.Count) direct files: $($cacheFiles -join ', ')"

                    $expandedFiles = Get-ChildItem -Path $cacheDirectories -Recurse -File
                    Write-Verbose "Found $($expandedFiles.Count) files in directories"

                    foreach ($efile in $expandedFiles) {
                        Write-Verbose "Processing expanded file: $($efile.FullName)"

                        # Combine expanded file with direct cache files and remove duplicates
                        $readfiles = @($efile.FullName) + @($cacheFiles) | Select-Object -Unique
                        Write-Verbose "Using read files: $($readfiles -join ', ')"

                        $aiParams = @{
                            Message   = $cmdPrompt
                            File      = $filename
                            Model     = $Model
                            Tool      = $Tool
                            AutoTest  = $AutoTest
                            PassCount = $PassCount
                        }

                        if ($PSBOUndParameters.ContainsKey('ReasoningEffort')) {
                            $aiParams.ReasoningEffort = $ReasoningEffort
                        }

                        # Add tool-specific parameters
                        if ($Tool -eq 'Aider') {
                            $aiParams.YesAlways = $true
                            $aiParams.NoStream = $true
                            $aiParams.CachePrompts = $true
                            $aiParams.ReadFile = $readfiles
                        } else {
                            # For Claude Code, use different approach for context files
                            $aiParams.ContextFiles = $readfiles
                        }

                        Write-Verbose "Invoking $Tool to update test file"
                        Write-Progress -Activity "Updating Pester Tests with $Tool" -Status "Updating and migrating $cmdName ($currentCommand/$totalCommands)" -PercentComplete (($currentCommand / $totalCommands) * 100)
                        Invoke-AITool @aiParams
                    }
                } else {
                    Write-Verbose "CacheFilePath does not contain directories, using files as-is"
                    Write-Verbose "Using cache files: $($cacheFiles -join ', ')"

                    # Remove duplicates from cache files
                    $readfiles = $cacheFiles | Select-Object -Unique

                    $aiParams = @{
                        Message   = $cmdPrompt
                        File      = $filename
                        Model     = $Model
                        Tool      = $Tool
                        AutoTest  = $AutoTest
                        PassCount = $PassCount
                    }

                    if ($PSBOUndParameters.ContainsKey('ReasoningEffort')) {
                        $aiParams.ReasoningEffort = $ReasoningEffort
                    }

                    # Add tool-specific parameters
                    if ($Tool -eq 'Aider') {
                        $aiParams.YesAlways = $true
                        $aiParams.NoStream = $true
                        $aiParams.CachePrompts = $true
                        $aiParams.ReadFile = $readfiles
                    } else {
                        # For Claude Code, use different approach for context files
                        $aiParams.ContextFiles = $readfiles
                    }

                    Write-Verbose "Invoking $Tool to update test file"
                    Write-Progress -Activity "Updating Pester Tests with $Tool" -Status "Processing $cmdName ($currentCommand/$totalCommands)" -PercentComplete (($currentCommand / $totalCommands) * 100)
                    Invoke-AITool @aiParams
                }

                # AutoFix workflow - run PSScriptAnalyzer and fix violations if found
                if (-not $NoAuthFix) {
                    Write-Verbose "Running AutoFix for $cmdName"
                    $autoFixParams = @{
                        FilePath     = $filename
                        SettingsPath = $SettingsPath
                        AiderParams  = $aiParams
                        MaxRetries   = $MaxRetries
                        Model        = $AutoFixModel
                        Tool         = $Tool
                    }

                    if ($PSBOUndParameters.ContainsKey('ReasoningEffort')) {
                        $aiParams.ReasoningEffort = $ReasoningEffort
                    }
                    Invoke-AutoFix @autoFixParams
                }
            }
        }

        # Clear progress bar when complete
        Write-Progress -Activity "Updating Pester Tests" -Status "Complete" -Completed
    }
}