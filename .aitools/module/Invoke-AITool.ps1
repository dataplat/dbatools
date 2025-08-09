function Invoke-AITool {
    <#
    .SYNOPSIS
        Invokes AI tools (Aider or Claude Code) to modify code files.

    .DESCRIPTION
        This function provides a unified interface for invoking AI coding tools like Aider and Claude Code.
        It can process single files or multiple files, apply AI-driven modifications, and optionally run tests.

    .PARAMETER Message
        The message or prompt to send to the AI tool.

    .PARAMETER File
        The file(s) to be processed by the AI tool.

    .PARAMETER Model
        The AI model to use (e.g., azure/gpt-4o, gpt-4o-mini, claude-3-5-sonnet for Aider; claude-sonnet-4-20250514 for Claude Code).

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: Aider, Claude
        Default: Claude

    .PARAMETER AutoTest
        If specified, automatically runs tests after making changes.

    .PARAMETER PassCount
        Number of passes to make with the AI tool. Sometimes multiple passes are needed for complex changes.

    .PARAMETER ReadFile
        Additional files to read for context (Aider-specific).

    .PARAMETER ContextFiles
        Additional files to provide as context (Claude Code-specific).

    .PARAMETER YesAlways
        Automatically answer yes to all prompts (Aider-specific).

    .PARAMETER NoStream
        Disable streaming output (Aider-specific).

    .PARAMETER CachePrompts
        Enable prompt caching (Aider-specific).

    .PARAMETER ReasoningEffort
        Controls the reasoning effort level for AI model responses.
        Valid values are: minimal, medium, high.

    .NOTES
        Tags: AI, Automation, CodeGeneration
        Author: dbatools team

    .EXAMPLE
        PS C:/> Invoke-AITool -Message "Fix this function" -File "C:/test.ps1" -Tool Claude
        Uses Claude Code to fix the specified file.

    .EXAMPLE
        PS C:/> Invoke-AITool -Message "Add error handling" -File "C:/test.ps1" -Tool Aider -Model "gpt-4o"
        Uses Aider with GPT-4o to add error handling to the file.

    .EXAMPLE
        PS C:/> Invoke-AITool -Message "Refactor this code" -File @("file1.ps1", "file2.ps1") -Tool Claude -PassCount 2
        Uses Claude Code to refactor multiple files with 2 passes.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string[]]$File,
        [string]$Model,
        [ValidateSet('Aider', 'Claude')]
        [string]$Tool = 'Claude',
        [switch]$AutoTest,
        [int]$PassCount = 1,
        [string[]]$ReadFile,
        [string[]]$ContextFiles,
        [switch]$YesAlways,
        [switch]$NoStream,
        [switch]$CachePrompts,
        [ValidateSet('minimal', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-Verbose "Invoking $Tool with message: $Message"
    Write-Verbose "Processing files: $($File -join ', ')"

    if ($Tool -eq 'Aider') {
        # Validate Aider is available
        if (-not (Get-Command aider -ErrorAction SilentlyContinue)) {
            throw "Aider is not installed or not in PATH. Please install Aider first."
        }

        # Build Aider command
        $aiderArgs = @()

        if ($Model) {
            $aiderArgs += "--model", $Model
        }

        if ($YesAlways) {
            $aiderArgs += "--yes-always"
        }

        if ($NoStream) {
            $aiderArgs += "--no-stream"
        }

        if ($CachePrompts) {
            $aiderArgs += "--cache-prompts"
        }

        if ($ReadFile) {
            foreach ($readFile in $ReadFile) {
                $aiderArgs += "--read", $readFile
            }
        }

        # Add files to modify
        $aiderArgs += $File

        # Add message
        $aiderArgs += "--message", $Message

        Write-Verbose "Aider command: aider $($aiderArgs -join ' ')"

        for ($pass = 1; $pass -le $PassCount; $pass++) {
            Write-Verbose "Aider pass $pass of $PassCount"

            try {
                & aider @aiderArgs
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Aider exited with code $LASTEXITCODE on pass $pass"
                }
            } catch {
                Write-Error "Failed to execute Aider on pass $pass`: $_"
                throw
            }
        }

    } elseif ($Tool -eq 'Claude') {
        # Claude Code implementation
        Write-Verbose "Using Claude Code for AI processing"

        # Build Claude Code parameters
        $claudeParams = @{
            Message = $Message
            Files = $File
        }

        if ($Model) {
            $claudeParams.Model = $Model
        }

        if ($ContextFiles) {
            $claudeParams.ContextFiles = $ContextFiles
        }

        if ($PSBoundParameters.ContainsKey('ReasoningEffort')) {
            $claudeParams.ReasoningEffort = $ReasoningEffort
        }

        for ($pass = 1; $pass -le $PassCount; $pass++) {
            Write-Verbose "Claude Code pass $pass of $PassCount"

            try {
                # This would be the actual Claude Code invocation
                # For now, this is a placeholder for the actual implementation
                Write-Verbose "Claude Code parameters: $($claudeParams | ConvertTo-Json -Depth 2)"

                # Placeholder for actual Claude Code execution
                # In a real implementation, this would call the Claude Code API or executable
                Write-Information "Claude Code would process: $($File -join ', ') with message: $Message" -InformationAction Continue

            } catch {
                Write-Error "Failed to execute Claude Code on pass $pass`: $_"
                throw
            }
        }
    }

    # Run tests if requested
    if ($AutoTest) {
        Write-Verbose "Running tests after AI modifications"

        foreach ($fileToTest in $File) {
            $testFile = $fileToTest -replace '\.ps1$', '.Tests.ps1'

            if (Test-Path $testFile) {
                Write-Verbose "Running tests for $testFile"
                try {
                    Invoke-Pester -Path $testFile -Output Detailed
                } catch {
                    Write-Warning "Test execution failed for $testFile`: $_"
                }
            } else {
                Write-Verbose "No test file found for $fileToTest (looked for $testFile)"
            }
        }
    }

    Write-Verbose "$Tool processing completed for $($File.Count) file(s)"
}