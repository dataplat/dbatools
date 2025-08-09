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
    [CmdletBinding()]
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
            Import-Module $PSScriptRoot/../dbatools.psm1 -Force -Verbose:$false
            Write-Progress -Activity "Loading dbatools Module" -Status "Complete" -PercentComplete 100
            Start-Sleep -Milliseconds 100
            Write-Progress -Activity "Loading dbatools Module" -Completed
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
                    $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($object.Name) -replace '\.Tests$', ''
                    $commands += $baseCommands | Where-Object Name -eq $cmdName
                }
                'System.Management.Automation.CommandInfo' {
                    Write-Verbose "Processing CommandInfo object: $($object.Name)"
                    $commands += $object
                }
                'System.String' {
                    Write-Verbose "Processing string path: $object"
                    if (Test-Path $object) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($object) -replace '\.Tests$', ''
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

            $aiParams = @{
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
                            $aiParams[$paramName] = $paramValue
                        }
                    } else {
                        # Aider - exclude Claude-only params if any exist in the future
                        $aiParams[$paramName] = $paramValue
                    }
                }

            if (-not $PSBoundParameters.Model) {
                $aiParams.Model = $Model
            }

            Write-Verbose "Invoking $Tool for $cmdName"
            try {
                Invoke-AITool @aiParams
                Write-Verbose "$Tool completed successfully for $cmdName"
            } catch {
                Write-Error "Error executing $Tool for $cmdName`: $_"
                Write-Verbose "$Tool failed for $cmdName with error: $_"
            }
        }
        Write-Verbose "Repair-SmallThing completed"
    }
}