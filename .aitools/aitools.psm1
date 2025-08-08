$PSDefaultParameterValues['Import-Module:Verbose'] = $false

# Auto-configure aider environment variables for .aitools directory
try {
    $env:AIDER_CONFIG_FILE = (Resolve-Path "$PSScriptRoot/.aider.conf.yml").Path
    $env:AIDER_ENV_FILE = (Resolve-Path "$PSScriptRoot/.env").Path
    $env:AIDER_MODEL_SETTINGS_FILE = (Resolve-Path "$PSScriptRoot/.aider.model.settings.yml").Path
    $env:AIDER_INPUT_HISTORY_FILE = (Resolve-Path "$PSScriptRoot/.aider/aider.input.history").Path
    $env:AIDER_CHAT_HISTORY_FILE = (Resolve-Path "$PSScriptRoot/.aider/aider.chat.history.md").Path
    $env:AIDER_LLM_HISTORY_FILE = (Resolve-Path "$PSScriptRoot/.aider/aider.llm.history").Path
    Write-Verbose "Aider environment configured for .aitools directory"
} catch {
    Write-Verbose "Could not configure aider environment: $_"
}

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

    .PARAMETER AutoFix
        If specified, automatically runs PSScriptAnalyzer after AI modifications and attempts to fix any violations found.
        This feature runs separately from PassCount iterations and uses targeted fix messages.

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
        [PSObject[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = @((Resolve-Path "$PSScriptRoot/prompts/prompt.md" -ErrorAction SilentlyContinue).Path),
        [string[]]$CacheFilePath = @(
            (Resolve-Path "$PSScriptRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/../private/testing/Get-TestConfig.ps1" -ErrorAction SilentlyContinue).Path
        ),
        [int]$MaxFileSize = 500kb,
        [string]$Model,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [switch]$AutoTest,
        [int]$PassCount = 1,
        [switch]$AutoFix,
        [string]$AutoFixModel = $Model,
        [int]$MaxRetries = 3,
        [string]$SettingsPath = (Resolve-Path "$PSScriptRoot/../tests/PSScriptAnalyzerRules.psd1" -ErrorAction SilentlyContinue).Path,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )
    begin {
        # Full prompt path
        if (-not (Get-Module dbatools.library -ListAvailable)) {
            Write-Warning "dbatools.library not found, installing"
            Install-Module dbatools.library -Scope CurrentUser -Force
        }
        Import-Module $PSScriptRoot/../dbatools.psm1 -Force

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
                    $path = (Resolve-Path $item.FullName).Path
                    Write-Verbose "Processing FileInfo path: $path"
                    if (Test-Path $path) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($path) -replace '/.Tests$', ''
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
                            $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedItem) -replace '/.Tests$', ''
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
        if (-not $commandsToProcess) {
            Write-Verbose "No input objects provided, getting commands from dbatools module"
            $commandsToProcess = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
        }

        # Get total count for progress tracking
        $totalCommands = $commandsToProcess.Count
        $currentCommand = 0

        foreach ($command in $commandsToProcess) {
            $currentCommand++
            $cmdName = $command.Name
            $filename = (Resolve-Path "$PSScriptRoot/../tests/$cmdName.Tests.ps1" -ErrorAction SilentlyContinue).Path

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
                if ($AutoFix) {
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

function Invoke-AITool {
    <#
    .SYNOPSIS
        Invokes AI coding tools (Aider or Claude Code).

    .DESCRIPTION
        The Invoke-AITool function provides a PowerShell interface to AI pair programming tools.
        It supports both Aider and Claude Code with their respective CLI options and can accept files via pipeline from Get-ChildItem.

    .PARAMETER Message
        The message to send to the AI. This is the primary way to communicate your intent.

    .PARAMETER File
        The files to edit. Can be piped in from Get-ChildItem.

    .PARAMETER Model
        The AI model to use (e.g., gpt-4, claude-3-opus-20240229 for Aider; claude-sonnet-4-20250514 for Claude Code).

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER EditorModel
        The model to use for editor tasks (Aider only).

    .PARAMETER NoPretty
        Disable pretty, colorized output (Aider only).

    .PARAMETER NoStream
        Disable streaming responses (Aider only).

    .PARAMETER YesAlways
        Always say yes to every confirmation (Aider only).

    .PARAMETER CachePrompts
        Enable caching of prompts (Aider only).

    .PARAMETER MapTokens
        Suggested number of tokens to use for repo map (Aider only).

    .PARAMETER MapRefresh
        Control how often the repo map is refreshed (Aider only).

    .PARAMETER NoAutoLint
        Disable automatic linting after changes (Aider only).

    .PARAMETER AutoTest
        Enable automatic testing after changes.

    .PARAMETER ShowPrompts
        Print the system prompts and exit (Aider only).

    .PARAMETER EditFormat
        Specify what edit format the LLM should use (Aider only).

    .PARAMETER MessageFile
        Specify a file containing the message to send (Aider only).

    .PARAMETER ReadFile
        Specify read-only files (Aider only).

    .PARAMETER ContextFiles
        Specify context files for Claude Code.

    .PARAMETER Encoding
        Specify the encoding for input and output (Aider only).

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .PARAMETER PassCount
        Number of passes to run.

    .PARAMETER DangerouslySkipPermissions
        Skip permission prompts (Claude Code only).

    .PARAMETER OutputFormat
        Output format for Claude Code (text, json, stream-json).

    .PARAMETER Verbose
        Enable verbose output for Claude Code.

    .PARAMETER MaxTurns
        Maximum number of turns for Claude Code.

    .EXAMPLE
        Invoke-AITool -Message "Fix the bug" -File script.ps1 -Tool Aider

        Asks Aider to fix a bug in script.ps1.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Message "Add error handling" -Tool Claude

        Adds error handling to all PowerShell files in the current directory using Claude Code.

    .EXAMPLE
        Invoke-AITool -Message "Update API" -Model claude-sonnet-4-20250514 -Tool Claude -DangerouslySkipPermissions

        Uses Claude Code with Sonnet 4 to update API code without permission prompts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$File,
        [string]$Model,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [string]$EditorModel,
        [switch]$NoPretty,
        [switch]$NoStream,
        [switch]$YesAlways,
        [switch]$CachePrompts,
        [int]$MapTokens,
        [ValidateSet('auto', 'always', 'files', 'manual')]
        [string]$MapRefresh,
        [switch]$NoAutoLint,
        [switch]$AutoTest,
        [switch]$ShowPrompts,
        [string]$EditFormat,
        [string]$MessageFile,
        [string[]]$ReadFile,
        [string[]]$ContextFiles,
        [ValidateSet('utf-8', 'ascii', 'unicode', 'utf-16', 'utf-32', 'utf-7')]
        [string]$Encoding,
        [int]$PassCount = 1,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort,
        [switch]$DangerouslySkipPermissions,
        [ValidateSet('text', 'json', 'stream-json')]
        [string]$OutputFormat,
        [int]$MaxTurns
    )

    begin {
        $allFiles = @()

        # Validate tool availability and parameters
        if ($Tool -eq 'Aider') {
            if (-not (Get-Command -Name aider -ErrorAction SilentlyContinue)) {
                throw "Aider executable not found. Please ensure it is installed and in your PATH."
            }

            # Warn about Claude-only parameters when using Aider
            if ($PSBoundParameters.ContainsKey('DangerouslySkipPermissions')) {
                Write-Warning "DangerouslySkipPermissions parameter is Claude Code-specific and will be ignored when using Aider"
            }
            if ($PSBoundParameters.ContainsKey('OutputFormat')) {
                Write-Warning "OutputFormat parameter is Claude Code-specific and will be ignored when using Aider"
            }
            if ($PSBoundParameters.ContainsKey('MaxTurns')) {
                Write-Warning "MaxTurns parameter is Claude Code-specific and will be ignored when using Aider"
            }
            if ($PSBoundParameters.ContainsKey('ContextFiles')) {
                Write-Warning "ContextFiles parameter is Claude Code-specific and will be ignored when using Aider"
            }
        } else {
            # Claude Code
            if (-not (Get-Command -Name claude -ErrorAction SilentlyContinue)) {
                throw "Claude Code executable not found. Please ensure it is installed and in your PATH."
            }

            # Warn about Aider-only parameters when using Claude Code
            $aiderOnlyParams = @('EditorModel', 'NoPretty', 'NoStream', 'YesAlways', 'CachePrompts', 'MapTokens', 'MapRefresh', 'NoAutoLint', 'ShowPrompts', 'EditFormat', 'MessageFile', 'ReadFile', 'Encoding')
            foreach ($param in $aiderOnlyParams) {
                if ($PSBoundParameters.ContainsKey($param)) {
                    Write-Warning "$param parameter is Aider-specific and will be ignored when using Claude Code"
                }
            }
        }
    }

    process {
        if ($File) {
            $allFiles += $File
        }
    }

    end {
        for ($i = 0; $i -lt $PassCount; $i++) {
            if ($Tool -eq 'Aider') {
                $arguments = @()

                # Add files if any were specified or piped in
                if ($allFiles) {
                    $arguments += $allFiles
                }

                # Add mandatory message parameter
                if ($Message) {
                    $arguments += "--message", $Message
                }

                # Add optional parameters only if they are present
                if ($Model) {
                    $arguments += "--model", $Model
                }

                if ($EditorModel) {
                    $arguments += "--editor-model", $EditorModel
                }

                if ($NoPretty) {
                    $arguments += "--no-pretty"
                }

                if ($NoStream) {
                    $arguments += "--no-stream"
                }

                if ($YesAlways) {
                    $arguments += "--yes-always"
                }

                if ($CachePrompts) {
                    $arguments += "--cache-prompts"
                }

                if ($PSBoundParameters.ContainsKey('MapTokens')) {
                    $arguments += "--map-tokens", $MapTokens
                }

                if ($MapRefresh) {
                    $arguments += "--map-refresh", $MapRefresh
                }

                if ($NoAutoLint) {
                    $arguments += "--no-auto-lint"
                }

                if ($AutoTest) {
                    $arguments += "--auto-test"
                }

                if ($ShowPrompts) {
                    $arguments += "--show-prompts"
                }

                if ($EditFormat) {
                    $arguments += "--edit-format", $EditFormat
                }

                if ($MessageFile) {
                    $arguments += "--message-file", $MessageFile
                }

                if ($ReadFile) {
                    foreach ($rf in $ReadFile) {
                        $arguments += "--read", $rf
                    }
                }

                if ($Encoding) {
                    $arguments += "--encoding", $Encoding
                }

                if ($ReasoningEffort) {
                    $arguments += "--reasoning-effort", $ReasoningEffort
                }

                if ($VerbosePreference -eq 'Continue') {
                    Write-Verbose "Executing: aider $($arguments -join ' ')"
                }

                if ($PassCount -gt 1) {
                    Write-Verbose "Aider pass $($i + 1) of $PassCount"
                }

                aider @arguments

            } else {
                # Claude Code
                Write-Verbose "Preparing Claude Code execution"

                # Build the full message with context files
                $fullMessage = $Message

                # Add context files content to the message
                if ($ContextFiles) {
                    Write-Verbose "Processing $($ContextFiles.Count) context files"
                    foreach ($contextFile in $ContextFiles) {
                        if (Test-Path $contextFile) {
                            Write-Verbose "Adding context from: $contextFile"
                            try {
                                $contextContent = Get-Content $contextFile -Raw -ErrorAction Stop
                                if ($contextContent) {
                                    $fullMessage += "`n`nContext from $($contextFile):`n$contextContent"
                                }
                            } catch {
                                Write-Warning "Could not read context file $contextFile`: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Warning "Context file not found: $contextFile"
                        }
                    }
                }

                # Build arguments array
                $arguments = @()

                # Add non-interactive print mode FIRST
                $arguments += "-p", $fullMessage

                # Add the dangerous flag early
                if ($DangerouslySkipPermissions) {
                    $arguments += "--dangerously-skip-permissions"
                    Write-Verbose "Adding --dangerously-skip-permissions to avoid prompts"
                }

                # Add allowed tools
                $arguments += "--allowedTools", "Read,Write,Edit,Create,Replace"

                # Add optional parameters
                if ($Model) {
                    $arguments += "--model", $Model
                    Write-Verbose "Using model: $Model"
                }

                if ($OutputFormat) {
                    $arguments += "--output-format", $OutputFormat
                    Write-Verbose "Using output format: $OutputFormat"
                }

                if ($MaxTurns) {
                    $arguments += "--max-turns", $MaxTurns
                    Write-Verbose "Using max turns: $MaxTurns"
                }

                if ($VerbosePreference -eq 'Continue') {
                    $arguments += "--verbose"
                }

                # Add files if any were specified or piped in (FILES GO LAST)
                if ($allFiles) {
                    Write-Verbose "Adding files to arguments: $($allFiles -join ', ')"
                    $arguments += $allFiles
                }

                if ($PassCount -gt 1) {
                    Write-Verbose "Claude Code pass $($i + 1) of $PassCount"
                }

                Write-Verbose "Executing: claude $($arguments -join ' ')"

                try {
                    claude @arguments
                    Write-Verbose "Claude Code execution completed successfully"
                } catch {
                    Write-Error "Claude Code execution failed: $($_.Exception.Message)"
                    throw
                }
            }
        }
    }
}

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
        [string]$SettingsPath = (Resolve-Path "$PSScriptRoot/../tests/PSScriptAnalyzerRules.psd1" -ErrorAction SilentlyContinue).Path,
        [hashtable]$AiderParams,

        [int]$MaxRetries = 3,
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
        Import-Module $PSScriptRoot/../dbatools.psm1 -Force

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
        if (-not $commandsToProcess) {
            Write-Verbose "No input objects provided, getting commands from dbatools module"
            $commandsToProcess = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
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
            $filename = (Resolve-Path "$PSScriptRoot/../tests/$cmdName.Tests.ps1" -ErrorAction SilentlyContinue).Path

            # Show progress for every file being processed
            Write-Progress -Activity "Running AutoFix with $Tool" -Status "Scanning $cmdName ($currentCommand/$totalCommands)" -PercentComplete (($currentCommand / $totalCommands) * 100)

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

            if ($PSCmdlet.ShouldProcess($filename, "Run PSScriptAnalyzer fixes using $Tool")) {
                for ($pass = 1; $pass -le $PassCount; $pass++) {
                    if ($PassCount -gt 1) {
                        # Nested progress for multiple passes
                        Write-Progress -Id 1 -ParentId 0 -Activity "Pass $pass of $PassCount" -Status "Processing $cmdName" -PercentComplete (($pass / $PassCount) * 100)
                    }

                    # Run the fix process
                    $invokeParams = @{
                        FilePath      = $filename
                        SettingsPath  = $SettingsPath
                        MaxRetries    = $MaxRetries
                        Model         = $Model
                        Tool          = $Tool
                        AutoTest      = $AutoTest
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

function Invoke-AutoFixSingleFile {
    <#
    .SYNOPSIS
        Backward compatibility helper for single file AutoFix processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$SettingsPath,

        [Parameter(Mandatory)]
        [hashtable]$AiderParams,

        [Parameter(Mandatory)]
        [int]$MaxRetries,

        [string]$Model,

        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',

        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    $retryCount = 0

    # Initialize progress
    Write-Progress -Activity "AutoFix: $([System.IO.Path]::GetFileName($FilePath))" -Status "Starting..." -PercentComplete 0

    do {
        $retryCount++

        # Update progress for each retry attempt
        $percentComplete = [math]::Round(($retryCount / $MaxRetries) * 100, 2)
        Write-Progress -Activity "AutoFix: $([System.IO.Path]::GetFileName($FilePath))" -Status "Attempt $retryCount of $MaxRetries - Running PSScriptAnalyzer" -PercentComplete $percentComplete

        Write-Verbose "Running PSScriptAnalyzer on $FilePath (attempt $retryCount/$MaxRetries)"

        try {
            # Run PSScriptAnalyzer with the specified settings
            $scriptAnalyzerParams = @{
                Path        = $FilePath
                Settings    = $SettingsPath
                ErrorAction = "Stop"
                Verbose     = $false
            }

            $analysisResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams

            if (-not $analysisResults) {
                Write-Progress -Activity "AutoFix: $([System.IO.Path]::GetFileName($FilePath))" -Status "No violations found - Complete" -PercentComplete 100
                Write-Output "No PSScriptAnalyzer violations found for $(Split-Path $FilePath -Leaf)"
                break
            }

            # Update status when sending to AI
            Write-Progress -Activity "AutoFix: $([System.IO.Path]::GetFileName($FilePath))" -Status "Sending fix request to $Tool (Attempt $retryCount)" -PercentComplete $percentComplete

            Write-Verbose "Found $($analysisResults.Count) PSScriptAnalyzer violation(s)"

            # Format violations into a focused fix message
            $fixMessage = "The following are PSScriptAnalyzer violations that need to be fixed:`n`n"

            foreach ($result in $analysisResults) {
                $fixMessage += "Rule: $($result.RuleName)`n"
                $fixMessage += "Line: $($result.Line)`n"
                $fixMessage += "Message: $($result.Message)`n`n"
            }

            $fixMessage += "CONSIDER THIS WITH PESTER CONTEXTS AND SCOPES WHEN DECIDING IF SCRIPT ANALYZER IS RIGHT."

            Write-Verbose "Sending focused fix request to $Tool"

            # Create modified parameters for the fix attempt
            $fixParams = $AiderParams.Clone()
            $fixParams.Message = $fixMessage
            $fixParams.Tool = $Tool

            # Remove tool-specific context parameters for focused fixes
            if ($Tool -eq 'Aider') {
                if ($fixParams.ContainsKey('ReadFile')) {
                    $fixParams.Remove('ReadFile')
                }
            } else {
                # Claude Code
                if ($fixParams.ContainsKey('ContextFiles')) {
                    $fixParams.Remove('ContextFiles')
                }
            }

            # Ensure we have the model parameter
            if ($Model -and -not $fixParams.ContainsKey('Model')) {
                $fixParams.Model = $Model
            }

            # Ensure we have the reasoning effort parameter
            if ($ReasoningEffort -and -not $fixParams.ContainsKey('ReasoningEffort')) {
                $fixParams.ReasoningEffort = $ReasoningEffort
            }

            # Invoke the AI tool with the focused fix message
            Invoke-AITool @fixParams
        } catch {
            Write-Warning "Failed to run PSScriptAnalyzer on $FilePath`: $($_.Exception.Message)"
            break
        }

    } while ($retryCount -lt $MaxRetries)

    # Clear progress
    Write-Progress -Activity "AutoFix: $([System.IO.Path]::GetFileName($FilePath))" -Status "Complete" -Completed

    if ($retryCount -eq $MaxRetries) {
        Write-Warning "AutoFix reached maximum retry limit ($MaxRetries) for $FilePath"
    }
}

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

    $retryCount = 0

    # Initialize progress
    Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Starting..." -PercentComplete 0

    do {
        $retryCount++

        # Update progress for each retry attempt
        $percentComplete = [math]::Round(($retryCount / $MaxRetries) * 100, 2)
        Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Attempt $retryCount of $MaxRetries - Running PSScriptAnalyzer" -PercentComplete $percentComplete

        Write-Verbose "Running PSScriptAnalyzer on $FilePath (attempt $retryCount/$MaxRetries)"

        try {
            # Run PSScriptAnalyzer with the specified settings
            $scriptAnalyzerParams = @{
                Path        = $FilePath
                Settings    = $SettingsPath
                ErrorAction = "Stop"
            }

            $analysisResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams

            if (-not $analysisResults) {
                Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "No violations found - Complete" -PercentComplete 100
                Write-Output "No PSScriptAnalyzer violations found for $(Split-Path $FilePath -Leaf)"
                break
            }

            # Update status when sending to AI
            Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Sending fix request to $Tool (Attempt $retryCount)" -PercentComplete $percentComplete

            Write-Verbose "Found $($analysisResults.Count) PSScriptAnalyzer violation(s)"

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
                Message   = $fixMessage
                File      = $FilePath
                Model     = $Model
                Tool      = $Tool
                AutoTest  = $AutoTest
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
        } catch {
            Write-Warning "Failed to run PSScriptAnalyzer on $FilePath`: $($_.Exception.Message)"
            break
        }

    } while ($retryCount -lt $MaxRetries)

    # Clear progress
    Write-Progress -Activity "AutoFixProcess: $([System.IO.Path]::GetFileName($FilePath))" -Status "Complete" -Completed

    if ($retryCount -eq $MaxRetries) {
        Write-Warning "AutoFix reached maximum retry limit ($MaxRetries) for $FilePath"
    }
}

function Repair-Error {
    <#
    .SYNOPSIS
        Repairs errors in dbatools Pester test files.

    .DESCRIPTION
        Processes and repairs errors found in dbatools Pester test files. This function reads error
        information from a JSON file and attempts to fix the identified issues in the test files.

    .PARAMETER First
        Specifies the maximum number of commands to process.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing.

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to "./aitools/prompts/fix-errors.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "./aitools/prompts/conventions.md".

    .PARAMETER ErrorFilePath
        The path to the JSON file containing error information.
        Defaults to "./aitools/prompts/errors.json".

    .NOTES
        Tags: Testing, Pester, ErrorHandling
        Author: dbatools team

    .EXAMPLE
        PS C:/> Repair-Error
        Processes and attempts to fix all errors found in the error file using default parameters.

    .EXAMPLE
        PS C:/> Repair-Error -ErrorFilePath "custom-errors.json"
        Processes and repairs errors using a custom error file.
    #>
    [CmdletBinding()]
    param (
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = (Resolve-Path "$PSScriptRoot/prompts/fix-errors.md" -ErrorAction SilentlyContinue).Path,
        [string[]]$CacheFilePath = @(
            (Resolve-Path "$PSScriptRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path
        ),
        [string]$ErrorFilePath = (Resolve-Path "$PSScriptRoot/prompts/errors.json" -ErrorAction SilentlyContinue).Path
    )

    $promptTemplate = if ($PromptFilePath -and (Test-Path $PromptFilePath)) {
        Get-Content $PromptFilePath
    } else {
        @("Error template not found")
    }
    $testerrors = if ($ErrorFilePath -and (Test-Path $ErrorFilePath)) {
        Get-Content $ErrorFilePath | ConvertFrom-Json
    } else {
        @()
    }
    $commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

    foreach ($command in $commands) {
        $filename = (Resolve-Path "$PSScriptRoot/../tests/$command.Tests.ps1" -ErrorAction SilentlyContinue).Path
        Write-Output "Processing $command"

        if (-not (Test-Path $filename)) {
            Write-Warning "No tests found for $command, file not found"
            continue
        }

        $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $command

        $testerr = $testerrors | Where-Object Command -eq $command
        foreach ($err in $testerr) {
            $cmdPrompt += "`n`n"
            $cmdPrompt += "Error: $($err.ErrorMessage)`n"
            $cmdPrompt += "Line: $($err.LineNumber)`n"
        }

        $aiderParams = @{
            Message      = $cmdPrompt
            File         = $filename
            NoStream     = $true
            CachePrompts = $true
            ReadFile     = $CacheFilePath
        }

        Invoke-AITool @aiderParams
    }
}





function Repair-Error {
    <#
    .SYNOPSIS
        Repairs errors in dbatools Pester test files.

    .DESCRIPTION
        Processes and repairs errors found in dbatools Pester test files. This function reads error
        information from a JSON file and attempts to fix the identified issues in the test files.

    .PARAMETER First
        Specifies the maximum number of commands to process.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing.

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to "./aitools/prompts/fix-errors.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "./aitools/prompts/conventions.md".

    .PARAMETER ErrorFilePath
        The path to the JSON file containing error information.
        Defaults to "./aitools/prompts/errors.json".

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER Model
        The AI model to use (e.g., gpt-4, claude-3-opus-20240229 for Aider; claude-sonnet-4-20250514 for Claude Code).

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        Tags: Testing, Pester, ErrorHandling, AITools
        Author: dbatools team

    .EXAMPLE
        PS C:/> Repair-Error
        Processes and attempts to fix all errors found in the error file using default parameters with Claude Code.

    .EXAMPLE
        PS C:/> Repair-Error -ErrorFilePath "custom-errors.json" -Tool Aider
        Processes and repairs errors using a custom error file with Aider.

    .EXAMPLE
        PS C:/> Repair-Error -Tool Claude -Model claude-sonnet-4-20250514
        Processes errors using Claude Code with Sonnet 4 model.
    #>
    [CmdletBinding()]
    param (
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = (Resolve-Path "$PSScriptRoot/prompts/fix-errors.md" -ErrorAction SilentlyContinue).Path,
        [string[]]$CacheFilePath = @(
            (Resolve-Path "$PSScriptRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$PSScriptRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path
        ),
        [string]$ErrorFilePath = (Resolve-Path "$PSScriptRoot/prompts/errors.json" -ErrorAction SilentlyContinue).Path,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [string]$Model,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    begin {
        # Validate tool-specific parameters
        if ($Tool -eq 'Claude') {
            # Warn about Aider-only parameters when using Claude
            if ($PSBoundParameters.ContainsKey('NoStream')) {
                Write-Warning "NoStream parameter is Aider-specific and will be ignored when using Claude Code"
            }
            if ($PSBoundParameters.ContainsKey('CachePrompts')) {
                Write-Warning "CachePrompts parameter is Aider-specific and will be ignored when using Claude Code"
            }
        }
    }

    end {
        $promptTemplate = if ($PromptFilePath -and (Test-Path $PromptFilePath)) {
            Get-Content $PromptFilePath
        } else {
            @("Error template not found")
        }
        $testerrors = if ($ErrorFilePath -and (Test-Path $ErrorFilePath)) {
            Get-Content $ErrorFilePath | ConvertFrom-Json
        } else {
            @()
        }
        $commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

        foreach ($command in $commands) {
            $filename = (Resolve-Path "$PSScriptRoot/../tests/$command.Tests.ps1" -ErrorAction SilentlyContinue).Path
            Write-Output "Processing $command with $Tool"

            if (-not (Test-Path $filename)) {
                Write-Warning "No tests found for $command, file not found"
                continue
            }

            $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $command

            $testerr = $testerrors | Where-Object Command -eq $command
            foreach ($err in $testerr) {
                $cmdPrompt += "`n`n"
                $cmdPrompt += "Error: $($err.ErrorMessage)`n"
                $cmdPrompt += "Line: $($err.LineNumber)`n"
            }

            $aiderParams = @{
                Message = $cmdPrompt
                File    = $filename
                Tool    = $Tool
            }

            # Add tool-specific parameters
            if ($Tool -eq 'Aider') {
                $aiderParams.NoStream = $true
                $aiderParams.CachePrompts = $true
                $aiderParams.ReadFile = $CacheFilePath
            } else {
                # For Claude Code, use different approach for context files
                $aiderParams.ContextFiles = $CacheFilePath
            }

            # Add optional parameters if specified
            if ($Model) {
                $aiderParams.Model = $Model
            }

            if ($ReasoningEffort) {
                $aiderParams.ReasoningEffort = $ReasoningEffort
            }

            Invoke-AITool @aiderParams
        }
    }
}

function Repair-SmallThing {
    <#
    .SYNOPSIS
        Repairs small issues in dbatools test files using AI coding tools.

    .DESCRIPTION
        Processes and repairs small issues in dbatools test files. This function can use either
        predefined prompts for specific issue types or custom prompt templates.

    .PARAMETER InputObject
        Array of objects that can be either file paths, FileInfo objects, or command objects (from Get-Command).

    .PARAMETER First
        Specifies the maximum number of commands to process.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing.

    .PARAMETER Model
        The AI model to use (e.g., azure/gpt-4o, gpt-4o-mini for Aider; claude-sonnet-4-20250514 for Claude Code).

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.

    .PARAMETER Type
        Predefined prompt type to use.
        Valid values: ReorgParamTest

    .PARAMETER EditorModel
        The model to use for editor tasks (Aider only).

    .PARAMETER NoPretty
        Disable pretty, colorized output (Aider only).

    .PARAMETER NoStream
        Disable streaming responses (Aider only).

    .PARAMETER YesAlways
        Always say yes to every confirmation (Aider only).

    .PARAMETER CachePrompts
        Enable caching of prompts (Aider only).

    .PARAMETER MapTokens
        Suggested number of tokens to use for repo map (Aider only).

    .PARAMETER MapRefresh
        Control how often the repo map is refreshed (Aider only).

    .PARAMETER NoAutoLint
        Disable automatic linting after changes (Aider only).

    .PARAMETER AutoTest
        Enable automatic testing after changes.

    .PARAMETER ShowPrompts
        Print the system prompts and exit (Aider only).

    .PARAMETER EditFormat
        Specify what edit format the LLM should use (Aider only).

    .PARAMETER MessageFile
        Specify a file containing the message to send (Aider only).

    .PARAMETER ReadFile
        Specify read-only files (Aider only).

    .PARAMETER Encoding
        Specify the encoding for input and output (Aider only).

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        Tags: Testing, Pester, Repair
        Author: dbatools team

    .EXAMPLE
        PS C:/> Repair-SmallThing -Type ReorgParamTest
        Repairs parameter organization issues in test files using Claude Code.

    .EXAMPLE
        PS C:/> Get-ChildItem *.Tests.ps1 | Repair-SmallThing -Tool Aider -Type ReorgParamTest
        Repairs parameter organization issues in specified test files using Aider.

    .EXAMPLE
        PS C:/> Repair-SmallThing -PromptFilePath "custom-prompt.md" -Tool Claude
        Uses a custom prompt template with Claude Code to repair issues.
    #>
    [cmdletbinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("FullName", "FilePath", "File")]
        [object[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [string]$Model = "azure/gpt-4o-mini",
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [string[]]$PromptFilePath,
        [ValidateSet("ReorgParamTest")]
        [string]$Type,
        [string]$EditorModel,
        [switch]$NoPretty,
        [switch]$NoStream,
        [switch]$YesAlways,
        [switch]$CachePrompts,
        [int]$MapTokens,
        [string]$MapRefresh,
        [switch]$NoAutoLint,
        [switch]$AutoTest,
        [switch]$ShowPrompts,
        [string]$EditFormat,
        [string]$MessageFile,
        [string[]]$ReadFile,
        [string]$Encoding,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    begin {
        Write-Verbose "Starting Repair-SmallThing with Tool: $Tool"
        $allObjects = @()

        # Validate tool-specific parameters
        if ($Tool -eq 'Claude') {
            # Warn about Aider-only parameters when using Claude
            $aiderOnlyParams = @('EditorModel', 'NoPretty', 'NoStream', 'YesAlways', 'CachePrompts', 'MapTokens', 'MapRefresh', 'NoAutoLint', 'ShowPrompts', 'EditFormat', 'MessageFile', 'ReadFile', 'Encoding')
            foreach ($param in $aiderOnlyParams) {
                if ($PSBoundParameters.ContainsKey($param)) {
                    Write-Warning "$param parameter is Aider-specific and will be ignored when using Claude Code"
                }
            }
        }

        $prompts = @{
            ReorgParamTest = "Move the `$expected` parameter list AND the `$TestConfig.CommonParameters` part into the BeforeAll block, placing them after the `$command` assignment. Keep them within the BeforeAll block. Do not move or modify the initial `$command` assignment.

            If you can't find the `$expected` parameter list, do not make any changes.

            If it's already where it should be, do not make any changes."
        }
        Write-Verbose "Available prompt types: $($prompts.Keys -join ', ')"

        Write-Verbose "Checking for dbatools.library module"
        if (-not (Get-Module dbatools.library -ListAvailable)) {
            Write-Verbose "dbatools.library not found, installing"
            $installModuleParams = @{
                Name    = "dbatools.library"
                Scope   = "CurrentUser"
                Force   = $true
                Verbose = "SilentlyContinue"
            }
            Install-Module @installModuleParams
        }
        if (-not (Get-Module dbatools)) {
            Write-Verbose "Importing dbatools module from /workspace/dbatools.psm1"
            Import-Module $PSScriptRoot/../dbatools.psm1 -Force -Verbose:$false
        }

        if ($PromptFilePath) {
            Write-Verbose "Loading prompt template from $PromptFilePath"
            $promptTemplate = Get-Content $PromptFilePath
            Write-Verbose "Prompt template loaded: $promptTemplate"
        }

        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

        Write-Verbose "Getting base dbatools commands with First: $First, Skip: $Skip"
        $baseCommands = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
        Write-Verbose "Found $($baseCommands.Count) base commands"
    }

    process {
        if ($InputObject) {
            Write-Verbose "Adding objects to collection: $($InputObject -join ', ')"
            $allObjects += $InputObject
        }
    }

    end {
        Write-Verbose "Starting end block processing"

        if ($InputObject.Count -eq 0) {
            Write-Verbose "No input objects provided, getting commands from dbatools module"
            $allObjects += Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
        }

        if (-not $PromptFilePath -and -not $Type) {
            Write-Verbose "Neither PromptFilePath nor Type specified"
            throw "You must specify either PromptFilePath or Type"
        }

        # Process different input types
        $commands = @()
        foreach ($object in $allObjects) {
            switch ($object.GetType().FullName) {
                'System.IO.FileInfo' {
                    Write-Verbose "Processing FileInfo object: $($object.FullName)"
                    $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($object.Name) -replace '/.Tests$', ''
                    $commands += $baseCommands | Where-Object Name -eq $cmdName
                }
                'System.Management.Automation.CommandInfo' {
                    Write-Verbose "Processing CommandInfo object: $($object.Name)"
                    $commands += $object
                }
                'System.String' {
                    Write-Verbose "Processing string path: $object"
                    if (Test-Path $object) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($object) -replace '/.Tests$', ''
                        $commands += $baseCommands | Where-Object Name -eq $cmdName
                    } else {
                        Write-Warning "Path not found: $object"
                    }
                }
                'System.Management.Automation.FunctionInfo' {
                    Write-Verbose "Processing FunctionInfo object: $($object.Name)"
                    $commands += $object
                }
                default {
                    Write-Warning "Unsupported input type: $($object.GetType().FullName)"
                }
            }
        }

        Write-Verbose "Processing $($commands.Count) unique commands"
        $commands = $commands | Select-Object -Unique

        foreach ($command in $commands) {
            $cmdName = $command.Name
            Write-Verbose "Processing command: $cmdName with $Tool"

            $filename = (Resolve-Path "$PSScriptRoot/../tests/$cmdName.Tests.ps1" -ErrorAction SilentlyContinue).Path
            Write-Verbose "Using test path: $filename"

            if (-not (Test-Path $filename)) {
                Write-Warning "No tests found for $cmdName, file not found"
                continue
            }

            # if file is larger than MaxFileSize, skip
            if ((Get-Item $filename).Length -gt 7.5kb) {
                Write-Warning "Skipping $cmdName because it's too large"
                continue
            }

            if ($Type) {
                Write-Verbose "Using predefined prompt for type: $Type"
                $cmdPrompt = $prompts[$Type]
            } else {
                Write-Verbose "Getting parameters for $cmdName"
                $parameters = $command.Parameters.Values | Where-Object Name -notin $commonParameters
                $parameters = $parameters.Name -join ", "
                Write-Verbose "Command parameters: $parameters"

                Write-Verbose "Using template prompt with parameters substitution"
                $cmdPrompt = $promptTemplate -replace "--PARMZ--", $parameters
            }
            Write-Verbose "Final prompt: $cmdPrompt"

            $aiderParams = @{
                Message = $cmdPrompt
                File    = $filename
                Tool    = $Tool
            }

            $excludedParams = @(
                $commonParameters,
                'InputObject',
                'First',
                'Skip',
                'PromptFilePath',
                'Type',
                'Tool'
            )

            # Add non-excluded parameters based on tool
            $PSBoundParameters.GetEnumerator() |
                Where-Object Key -notin $excludedParams |
                ForEach-Object {
                    $paramName = $PSItem.Key
                    $paramValue = $PSItem.Value

                    # Filter out tool-specific parameters for the wrong tool
                    if ($Tool -eq 'Claude') {
                        $aiderOnlyParams = @('EditorModel', 'NoPretty', 'NoStream', 'YesAlways', 'CachePrompts', 'MapTokens', 'MapRefresh', 'NoAutoLint', 'ShowPrompts', 'EditFormat', 'MessageFile', 'ReadFile', 'Encoding')
                        if ($paramName -notin $aiderOnlyParams) {
                            $aiderParams[$paramName] = $paramValue
                        }
                    } else {
                        # Aider - exclude Claude-only params if any exist in the future
                        $aiderParams[$paramName] = $paramValue
                    }
                }

            if (-not $PSBoundParameters.Model) {
                $aiderParams.Model = $Model
            }

            Write-Verbose "Invoking $Tool for $cmdName"
            try {
                Invoke-AITool @aiderParams
                Write-Verbose "$Tool completed successfully for $cmdName"
            } catch {
                Write-Error "Error executing $Tool for $cmdName`: $_"
                Write-Verbose "$Tool failed for $cmdName with error: $_"
            }
        }
        Write-Verbose "Repair-SmallThing completed"
    }
}

Export-ModuleMember -Function Update-PesterTest, Invoke-AITool, Invoke-AutoFix, Repair-Error, Repair-SmallThing