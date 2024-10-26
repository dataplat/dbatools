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
        Defaults to "/workspace/.aider/prompts/template.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.

    .PARAMETER MaxFileSize
        The maximum size of test files to process, in bytes. Files larger than this will be skipped.
        Defaults to 8KB.

    .PARAMETER Model
        The AI model to use (e.g., azure/gpt-4o, gpt-4o-mini, claude-3-5-sonnet).

    .NOTES
        Tags: Testing, Pester
        Author: dbatools team

    .EXAMPLE
        PS C:\> Update-PesterTest
        Updates all eligible Pester tests to v5 format using default parameters.

    .EXAMPLE
        PS C:\> Update-PesterTest -First 10 -Skip 5
        Updates 10 test files starting from the 6th command, skipping the first 5.

    .EXAMPLE
        PS C:\> "C:\tests\Get-DbaDatabase.Tests.ps1", "C:\tests\Get-DbaBackup.Tests.ps1" | Update-PesterTest
        Updates the specified test files to v5 format.

    .EXAMPLE
        PS C:\> Get-Command -Module dbatools -Name "*Database*" | Update-PesterTest
        Updates test files for all commands in dbatools module that match "*Database*".

    .EXAMPLE
        PS C:\> Get-ChildItem ./tests/Add-DbaRegServer.Tests.ps1 | Update-PesterTest -Verbose
        Updates the specific test file from a Get-ChildItem result.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline)]
        [PSObject[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/template.md",
        [string[]]$CacheFilePath = @("/workspace/.aider/prompts/conventions.md","/workspace/private/testing/Get-TestConfig.ps1"),
        [int]$MaxFileSize = 8kb,
        [string]$Model
    )
    begin {
        # Full prompt path
        if (-not (Get-Module dbatools.library -ListAvailable)) {
            Write-Warning "dbatools.library not found, installing"
            Install-Module dbatools.library -Scope CurrentUser -Force
        }
        Import-Module /workspace/dbatools.psm1 -Force

        $promptTemplate = Get-Content $PromptFilePath
        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
        $commandsToProcess = @()
    }

    process {
        if ($InputObject) {
            foreach ($item in $InputObject) {
                Write-Verbose "Processing input object of type: $($item.GetType().FullName)"

                if ($item -is [System.Management.Automation.CommandInfo]) {
                    $commandsToProcess += $item
                } elseif ($item -is [System.IO.FileInfo]) {
                    $path = $item.FullName
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
                    if (Test-Path $item) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($item) -replace '\.Tests$', ''
                        Write-Verbose "Extracted command name: $cmdName"
                        $cmd = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
                        if ($cmd) {
                            $commandsToProcess += $cmd
                        } else {
                            Write-Warning "Could not find command for test file: $item"
                        }
                    } else {
                        Write-Warning "File not found: $item"
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

        foreach ($command in $commandsToProcess) {
            $cmdName = $command.Name
            $filename = "/workspace/tests/$cmdName.Tests.ps1"

            Write-Verbose "Processing command: $cmdName"
            Write-Verbose "Test file path: $filename"

            if (-not (Test-Path $filename)) {
                Write-Warning "No tests found for $cmdName"
                Write-Warning "$filename not found"
                continue
            }

            <# Check if it's already been converted #>
            if (Select-String -Path $filename -Pattern "HaveParameter") {
                Write-Warning "Skipping $cmdName because it's already been converted to Pester v5"
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

            if ($PSCmdlet.ShouldProcess($filename, "Update Pester test to v5 format and/or style")) {
                $aiderParams = @{
                    Message      = $cmdPrompt
                    File         = $filename
                    YesAlways    = $true
                    NoStream     = $true
                    CachePrompts = $true
                    ReadFile     = $CacheFilePath
                    Model        = $Model
                }

                Write-Verbose "Invoking Aider to update test file"
                Invoke-Aider @aiderParams
            }
        }
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
        Defaults to "/workspace/.aider/prompts/fix-errors.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "/workspace/.aider/prompts/conventions.md".

    .PARAMETER ErrorFilePath
        The path to the JSON file containing error information.
        Defaults to "/workspace/.aider/prompts/errors.json".

    .NOTES
        Tags: Testing, Pester, ErrorHandling
        Author: dbatools team

    .EXAMPLE
        PS C:\> Repair-Error
        Processes and attempts to fix all errors found in the error file using default parameters.

    .EXAMPLE
        PS C:\> Repair-Error -ErrorFilePath "custom-errors.json"
        Processes and repairs errors using a custom error file.
    #>
    [CmdletBinding()]
    param (
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/fix-errors.md",
        [string[]]$CacheFilePath = "/workspace/.aider/prompts/conventions.md",
        [string]$ErrorFilePath = "/workspace/.aider/prompts/errors.json"
    )

    $promptTemplate = Get-Content $PromptFilePath
    $testerrors = Get-Content $ErrorFilePath | ConvertFrom-Json
    $commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

    foreach ($command in $commands) {
        $filename = "/workspace/tests/$command.Tests.ps1"
        Write-Output "Processing $command"

        if (-not (Test-Path $filename)) {
            Write-Warning "No tests found for $command"
            Write-Warning "$filename not found"
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

        Invoke-Aider @aiderParams
    }
}

function Repair-SmallThing {
    [cmdletbinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("FullName", "FilePath", "File")]
        [object[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [string]$Model = "azure/gpt-4o-mini",
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
        [string]$Encoding
    )

    begin {
        Write-Verbose "Starting Repair-SmallThing"
        $allObjects = @()

        $prompts = @{
            ReorgParamTest = "Move the `$expected` parameter list AND the `$TestConfig.CommonParameters` part into the BeforeAll block, placing them after the `$command` assignment. Keep them within the BeforeAll block. Do not move or modify the initial `$command` assignment.

            If you can't find the `$expected` parameter list, do not make any changes.

            If it's already where it should be, do not make any changes."
        }
        Write-Verbose "Available prompt types: $($prompts.Keys -join ', ')"

        Write-Verbose "Checking for dbatools.library module"
        if (-not (Get-Module dbatools.library -ListAvailable)) {
            Write-Verbose "dbatools.library not found, installing"
            Install-Module dbatools.library -Scope CurrentUser -Force -Verbose:$false
        }
        if (-not (Get-Module dbatools)) {
            Write-Verbose "Importing dbatools module from /workspace/dbatools.psm1"
            Import-Module /workspace/dbatools.psm1 -Force -Verbose:$false
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
            Write-Verbose "Processing command: $cmdName"

            $filename = "/workspace/tests/$cmdName.Tests.ps1"
            Write-Verbose "Using test path: $filename"

            if (-not (Test-Path $filename)) {
                Write-Warning "No tests found for $cmdName"
                Write-Warning "$filename not found"
                continue
            }

            # if file is larger than MaxFileSize, skip
            if ((Get-Item $filename).Length -gt 8kb) {
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
            }

            $excludedParams = @(
                $commonParameters,
                'InputObject',
                'First',
                'Skip',
                'PromptFilePath',
                'Type'
            )

            $PSBoundParameters.GetEnumerator() |
                Where-Object Key -notin $excludedParams |
                ForEach-Object {
                    $aiderParams[$PSItem.Key] = $PSItem.Value
                }

            if (-not $PSBoundParameters.Model) {
                $aiderParams.Model = $Model
            }

            Write-Verbose "Invoking aider for $cmdName"
            try {
                Invoke-Aider @aiderParams
                Write-Verbose "Aider completed successfully for $cmdName"
            } catch {
                Write-Error "Error executing aider for $cmdName`: $_"
                Write-Verbose "Aider failed for $cmdName with error: $_"
            }
        }
        Write-Verbose "Repair-SmallThing completed"
    }
}

function Invoke-Aider {
    <#
    .SYNOPSIS
        Invokes the aider AI pair programming tool.

    .DESCRIPTION
        The Invoke-Aider function provides a PowerShell interface to the aider AI pair programming tool.
        It supports all aider CLI options and can accept files via pipeline from Get-ChildItem.

    .PARAMETER Message
        The message to send to the AI. This is the primary way to communicate your intent.

    .PARAMETER File
        The files to edit. Can be piped in from Get-ChildItem.

    .PARAMETER Model
        The AI model to use (e.g., gpt-4, claude-3-opus-20240229).

    .PARAMETER EditorModel
        The model to use for editor tasks.

    .PARAMETER NoPretty
        Disable pretty, colorized output.

    .PARAMETER NoStream
        Disable streaming responses.

    .PARAMETER YesAlways
        Always say yes to every confirmation.

    .PARAMETER CachePrompts
        Enable caching of prompts.

    .PARAMETER MapTokens
        Suggested number of tokens to use for repo map.

    .PARAMETER MapRefresh
        Control how often the repo map is refreshed.

    .PARAMETER NoAutoLint
        Disable automatic linting after changes.

    .PARAMETER AutoTest
        Enable automatic testing after changes.

    .PARAMETER ShowPrompts
        Print the system prompts and exit.

    .PARAMETER EditFormat
        Specify what edit format the LLM should use.

    .PARAMETER MessageFile
        Specify a file containing the message to send.

    .PARAMETER ReadFile
        Specify read-only files.

    .PARAMETER Encoding
        Specify the encoding for input and output.

    .EXAMPLE
        Invoke-Aider -Message "Fix the bug" -File script.ps1

        Asks aider to fix a bug in script.ps1.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-Aider -Message "Add error handling"

        Adds error handling to all PowerShell files in the current directory.

    .EXAMPLE
        Invoke-Aider -Message "Update API" -Model gpt-4 -NoStream

        Uses GPT-4 to update API code without streaming output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$File,
        [string]$Model,
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
        [ValidateSet('utf-8', 'ascii', 'unicode', 'utf-16', 'utf-32', 'utf-7')]
        [string]$Encoding
    )

    begin {
        $allFiles = @()

        if (-not (Get-Command -Name aider -ErrorAction SilentlyContinue)) {
            throw "Aider executable not found. Please ensure it is installed and in your PATH."
        }
    }

    process {
        if ($File) {
            $allFiles += $File
        }
    }

    end {
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
            foreach ($file in $ReadFile) {
                $arguments += "--read", $file
            }
        }

        if ($Encoding) {
            $arguments += "--encoding", $Encoding
        }

        if ($VerbosePreference -eq 'Continue') {
            Write-Verbose "Executing: aider $($arguments -join ' ')"
        }

        aider @arguments
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
        Defaults to "/workspace/.aider/prompts/fix-errors.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "/workspace/.aider/prompts/conventions.md".

    .PARAMETER ErrorFilePath
        The path to the JSON file containing error information.
        Defaults to "/workspace/.aider/prompts/errors.json".

    .NOTES
        Tags: Testing, Pester, ErrorHandling
        Author: dbatools team

    .EXAMPLE
        PS C:\> Repair-Error
        Processes and attempts to fix all errors found in the error file using default parameters.

    .EXAMPLE
        PS C:\> Repair-Error -ErrorFilePath "custom-errors.json"
        Processes and repairs errors using a custom error file.
    #>
    [CmdletBinding()]
    param (
        [int]$First = 10000,
        [int]$Skip,
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/fix-errors.md",
        [string[]]$CacheFilePath = "/workspace/.aider/prompts/conventions.md",
        [string]$ErrorFilePath = "/workspace/.aider/prompts/errors.json"
    )

    $promptTemplate = Get-Content $PromptFilePath
    $testerrors = Get-Content $ErrorFilePath | ConvertFrom-Json
    $commands = $testerrors | Select-Object -ExpandProperty Command -Unique | Sort-Object

    foreach ($command in $commands) {
        $filename = "/workspace/tests/$command.Tests.ps1"
        Write-Output "Processing $command"

        if (-not (Test-Path $filename)) {
            Write-Warning "No tests found for $command"
            Write-Warning "$filename not found"
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

        Invoke-Aider @aiderParams
    }
}