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
        Specifies the maximum number of commands to process. Defaults to 1000.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing. Defaults to 0.

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to "/workspace/.aider/prompts/template.md".

    .PARAMETER CacheFilePath
        The path to the file containing cached conventions.
        Defaults to "/workspace/.aider/prompts/conventions.md".

    .PARAMETER MaxFileSize
        The maximum size of test files to process, in bytes. Files larger than this will be skipped.
        Defaults to 8KB.

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
        [int]$First = 1000,
        [int]$Skip = 0,
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/template.md",
        [string[]]$CacheFilePath = "/workspace/.aider/prompts/conventions.md",
        [int]$MaxFileSize = 8kb
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

            # if it matches Should -HaveParameter then skip because it's been done
            if (Select-String -Path $filename -Pattern "Should -HaveParameter") {
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

            if ($PSCmdlet.ShouldProcess($filename, "Update Pester test to v5 format")) {
                $aiderParams = @{
                    Message      = $cmdPrompt
                    File         = $filename
                    YesAlways    = $true
                    Stream       = $false
                    CachePrompts = $true
                    ReadFile     = $CacheFilePath
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
        Specifies the maximum number of commands to process. Defaults to 1000.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing. Defaults to 0.

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
        [int]$First = 1000,
        [int]$Skip = 0,
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
            Stream       = $false
            CachePrompts = $true
            ReadFile     = $CacheFilePath
        }

        Invoke-Aider @aiderParams
    }
}

function Repair-ParameterTest {
    <#
    .SYNOPSIS
        Repairs parameter tests in dbatools Pester test files.

    .DESCRIPTION
        Processes and repairs parameter-related tests in dbatools Pester test files. This function
        specifically focuses on fixing parameter validation tests and ensures they follow the correct format.

    .PARAMETER First
        Specifies the maximum number of commands to process. Defaults to 1000.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing. Defaults to 0.

    .PARAMETER Model
        The AI model to use for processing. Defaults to "azure/gpt-4o-mini".

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to "/workspace/.aider/prompts/fix-errors.md".

    .NOTES
        Tags: Testing, Pester, Parameters
        Author: dbatools team

    .EXAMPLE
        PS C:\> Repair-ParameterTest
        Repairs parameter tests for all eligible commands using default parameters.

    .EXAMPLE
        PS C:\> Repair-ParameterTest -First 5 -Model "different-model"
        Repairs parameter tests for the first 5 commands using a specified AI model.
    #>
    [cmdletbinding()]
    param (
        [int]$First = 1000,
        [int]$Skip = 0,
        [string]$Model = "azure/gpt-4o-mini",
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/fix-errors.md"
    )
    # Full prompt path
    if (-not (Get-Module dbatools.library -ListAvailable)) {
        Write-Warning "dbatools.library not found, installing"
        Install-Module dbatools.library -Scope CurrentUser -Force
    }
    Import-Module /workspace/dbatools.psm1 -Force

    $promptTemplate = Get-Content $PromptFilePath

    $commands = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip
    $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters

    foreach ($command in $commands) {
        $cmdName = $command.Name
        $filename = "/workspace/tests/$cmdName.Tests.ps1"

        if (-not (Test-Path $filename)) {
            Write-Warning "No tests found for $cmdName"
            Write-Warning "$filename not found"
            continue
        }

        $parameters = $command.Parameters.Values | Where-Object Name -notin $commonParameters

        $parameters = $parameters.Name -join ", "
        $cmdPrompt = $promptTemplate -replace "--PARMZ--", $parameters

        $aiderParams = @{
            Message   = $cmdPrompt
            File      = $filename
            YesAlways = $true
            Stream    = $false
            Model     = $Model
        }

        Invoke-Aider @aiderParams
    }
}

function Invoke-Aider {
    <#
    .SYNOPSIS
        PowerShell wrapper for the aider CLI tool.

    .DESCRIPTION
        Provides a PowerShell interface to the aider command-line tool, allowing for easier integration
        with PowerShell scripts and workflows. Supports core functionality including model selection,
        caching, and various output options.

    .PARAMETER Message
        The message or prompt to send to aider.

    .PARAMETER File
        The file(s) to process with aider.

    .PARAMETER Model
        Specify the AI model to use (e.g., gpt-4o, claude-3-5-sonnet).

    .PARAMETER EditorModel
        Specify the model to use for editing code.

    .PARAMETER NoPretty
        Disable pretty, colorized output.

    .PARAMETER Stream
        Enable streaming responses. Cannot be used with -NoStream.

    .PARAMETER NoStream
        Disable streaming responses. Cannot be used with -Stream.

    .PARAMETER YesAlways
        Automatically confirm all prompts.

    .PARAMETER CachePrompts
        Enable caching of prompts to reduce token costs.

    .PARAMETER MapTokens
        Number of tokens to use for repo map. Use 0 to disable.

    .PARAMETER MapRefresh
        Control how often the repo map is refreshed (auto/always/files/manual).

    .PARAMETER NoAutoLint
        Disable automatic linting after changes.

    .PARAMETER AutoTest
        Enable automatic testing after changes.

    .PARAMETER ShowPrompts
        Show system prompts.

    .PARAMETER VerboseOutput
        Enable verbose output.

    .PARAMETER EditFormat
        Specify the edit format (e.g., 'whole' for whole file).

    .PARAMETER MessageFile
        File containing the message to send to aider.

    .PARAMETER ReadFile
        Specify read-only files.

    .PARAMETER Encoding
        Specify the encoding for input and output. Defaults to 'utf-8'.

    .NOTES
        Tags: AI, Automation
        Author: dbatools team

    .EXAMPLE
        PS C:\> Invoke-Aider -Message "Fix the bug" -File "script.ps1"
        Runs aider with the specified message and file.

    .EXAMPLE
        PS C:\> $params = @{
        >>     Message = "Update tests"
        >>     File = "tests.ps1"
        >>     Model = "gpt-4o"
        >>     CachePrompts = $true
        >> }
        PS C:\> Invoke-Aider @params
        Runs aider using GPT-4 model with prompt caching enabled.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string[]]$File,
        [string]$Model,
        [string]$EditorModel,
        [switch]$NoPretty,
        [Parameter(ParameterSetName = 'Stream')]
        [switch]$Stream,
        [Parameter(ParameterSetName = 'NoStream')]
        [switch]$NoStream,
        [switch]$YesAlways,
        [switch]$CachePrompts,
        [int]$MapTokens = 0,
        [ValidateSet('auto', 'always', 'files', 'manual')]
        [string]$MapRefresh = 'manual',
        [switch]$NoAutoLint,
        [switch]$AutoTest,
        [switch]$ShowPrompts,
        [switch]$VerboseOutput,
        [string]$EditFormat = 'whole',
        [string]$MessageFile,
        [string[]]$ReadFile,
        [ValidateSet('utf-8', 'ascii', 'unicode', 'utf-16', 'utf-32', 'utf-7')]
        [string]$Encoding = 'utf-8'
    )

    $params = @(
        "--message", $Message
    )

    foreach ($f in $File) {
        $params += "--file"
        $params += $f
    }

    if ($Model) {
        $params += "--model"
        $params += $Model
    }

    if ($EditorModel) {
        $params += "--editor-model"
        $params += $EditorModel
    }

    if ($NoPretty) {
        $params += "--no-pretty"
    }

    if ($Stream) {
        # Stream is enabled, so don't add --no-stream
    } elseif ($NoStream) {
        $params += "--no-stream"
    }

    if ($YesAlways) {
        $params += "--yes-always"
    }

    if ($CachePrompts) {
        $params += "--cache-prompts"
        # Always set keepalive pings to 5 when caching is enabled
        $params += "--cache-keepalive-pings"
        $params += "5"
    }

    if ($MapTokens -ge 0) {
        $params += "--map-tokens"
        $params += $MapTokens.ToString()
    }

    if ($MapRefresh) {
        $params += "--map-refresh"
        $params += $MapRefresh
    }

    if ($NoAutoLint) {
        $params += "--no-auto-lint"
    }

    if ($AutoTest) {
        $params += "--auto-test"
    }

    if ($ShowPrompts) {
        $params += "--show-prompts"
    }

    if ($VerboseOutput) {
        $params += "--verbose"
    }

    if ($EditFormat) {
        $params += "--edit-format"
        $params += $EditFormat
    }

    if ($MessageFile) {
        $params += "--message-file"
        $params += $MessageFile
    }

    foreach ($rf in $ReadFile) {
        $params += "--read"
        $params += $rf
    }

    if ($Encoding) {
        $params += "--encoding"
        $params += $Encoding
    }

    aider @params
}

function Repair-Error {
    <#
    .SYNOPSIS
        Repairs errors in dbatools Pester test files.

    .DESCRIPTION
        Processes and repairs errors found in dbatools Pester test files. This function reads error
        information from a JSON file and attempts to fix the identified issues in the test files.

    .PARAMETER First
        Specifies the maximum number of commands to process. Defaults to 1000.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing. Defaults to 0.

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
        [int]$First = 1000,
        [int]$Skip = 0,
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
            Stream       = $false
            CachePrompts = $true
            ReadFile     = $CacheFilePath
        }

        Invoke-Aider @aiderParams
    }
}