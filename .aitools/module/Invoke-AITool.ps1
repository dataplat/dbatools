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
        [string[]]$Message,
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
                foreach ($singlefile in $allfiles) {
                    $arguments = @()

                    # Add files if any were specified or piped in
                    if ($allFiles) {
                        $arguments += $allFiles
                    }

                    # Add mandatory message parameter
                    if ($Message) {
                        $arguments += "--message", ($Message -join ' ')
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

                    $results = aider @arguments

                    [pscustomobject]@{
                        FileName = (Split-Path $singlefile -Leaf)
                        Results  = "$results"
                    }

                    # Run Invoke-DbatoolsFormatter after AI tool execution
                    if (Test-Path $singlefile) {
                        Write-Verbose "Running Invoke-DbatoolsFormatter on $singlefile"
                        try {
                            Invoke-DbatoolsFormatter -Path $singlefile
                        } catch {
                            Write-Warning "Invoke-DbatoolsFormatter failed for $singlefile`: $($_.Exception.Message)"
                        }
                    }
                }

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

                foreach ($singlefile in $allFiles) {
                    # Build arguments array
                    $arguments = @()

                    # Add non-interactive print mode FIRST
                    $arguments += "-p", $fullMessage

                    # Add the dangerous flag early
                    if ($DangerouslySkipPermissions) {
                        $arguments += "--dangerously-skip-permissions"
                        Write-Verbose "Adding --dangerously-skip-permissions to avoid prompts"
                    } else {
                        # Add allowed tools
                        $arguments += "--allowedTools", "Read,Write,Edit,Create,Replace"
                    }

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
                        Write-Verbose "Adding file to arguments: $singlefile"
                        $arguments += $file
                    }

                    if ($PassCount -gt 1) {
                        Write-Verbose "Claude Code pass $($i + 1) of $PassCount"
                    }

                    Write-Verbose "Executing: claude $($arguments -join ' ')"

                    try {
                        $results = claude @arguments

                        [pscustomobject]@{
                            FileName = (Split-Path $singlefile -Leaf)
                            Results  = "$results"
                        }

                        Write-Verbose "Claude Code execution completed successfully"

                        # Run Invoke-DbatoolsFormatter after AI tool execution
                        if (Test-Path $singlefile) {
                            Write-Verbose "Running Invoke-DbatoolsFormatter on $singlefile"
                            try {
                                Invoke-DbatoolsFormatter -Path $singlefile
                            } catch {
                                Write-Warning "Invoke-DbatoolsFormatter failed for $singlefile`: $($_.Exception.Message)"
                            }
                        }
                    } catch {
                        Write-Error "Claude Code execution failed: $($_.Exception.Message)"
                        throw
                    }
                }
            }
        }
    }
}
