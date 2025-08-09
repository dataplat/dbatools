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
        Defaults to "prompts/fix-errors.md" relative to the module directory.

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "prompts/style.md" and "prompts/migration.md" relative to the module directory.

    .PARAMETER ErrorFilePath
        The path to the JSON file containing error information.
        Defaults to "prompts/errors.json" relative to the module directory.

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

        if (-not $testerrors) {
            Write-Warning "No errors found in error file: $ErrorFilePath"
            return
        }

        $commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

        # Apply First and Skip parameters to commands
        if ($Skip) {
            $commands = $commands | Select-Object -Skip $Skip
        }
        if ($First) {
            $commands = $commands | Select-Object -First $First
        }

        Write-Verbose "Processing $($commands.Count) commands with errors"

        foreach ($command in $commands) {
            $filename = (Resolve-Path "$script:ModulePath/tests/$command.Tests.ps1" -ErrorAction SilentlyContinue).Path
            Write-Verbose "Processing $command with $Tool"

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

            $aiParams = @{
                Message = $cmdPrompt
                File    = $filename
                Tool    = $Tool
            }

            # Add tool-specific parameters
            if ($Tool -eq 'Aider') {
                $aiParams.NoStream = $true
                $aiParams.CachePrompts = $true
                $aiParams.ReadFile = $CacheFilePath
            } else {
                # For Claude Code, use different approach for context files
                $aiParams.ContextFiles = $CacheFilePath
            }

            # Add optional parameters if specified
            if ($Model) {
                $aiParams.Model = $Model
            }

            if ($ReasoningEffort) {
                $aiParams.ReasoningEffort = $ReasoningEffort
            }

            Write-Verbose "Invoking $Tool to repair errors in $command"
            Invoke-AITool @aiParams
        }

        Write-Verbose "Repair-Error completed processing $($commands.Count) commands"
    }
}