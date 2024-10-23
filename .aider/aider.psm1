function Update-PesterTest {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [int]$First = 1000,
        [int]$Skip = 0,
        [string[]]$PromptFilePath = "/workspace/.aider/prompts/template.md",
        [string[]]$CacheFilePath = "/workspace/.aider/prompts/conventions.md",
        [int]$MaxFileSize = 8kb
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

        # if it matches Should -HaveParameter then skip becuase it's been done
        if (Select-String -Path $filename -Pattern "Should -HaveParameter") {
            Write-Warning "Skipping $cmdName because it's already been converted to Pester v5"
            continue
        }

        # if file is larger than 8kb, skip
        if ((Get-Item $filename).Length -gt $MaxFileSize) {
            Write-Warning "Skipping $cmdName because it's too large"
            continue
        }

        $parameters = $command.Parameters.Values | Where-Object Name -notin $commonParameters
        $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $cmdName
        $cmdPrompt = $cmdPrompt -replace "--PARMZ--", ($parameters.Name -join "`n")
        $cmdprompt = $cmdPrompt -join "`n"

        $params = @(
            "--message", $cmdPrompt,
            "--file", $filename,
            "--yes-always",
            "--no-stream",
            "--cache-prompts",
            "--read", $CacheFilePath
        )

        aider @params
    }
}

function Repair-Error {
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

        # Run Aider in non-interactive mode with auto-confirmation
        $parms = @(
            "--message", $cmdPrompt,
            "--file", $filename,
            "--no-stream",
            "--cache-prompts",
            "--read", $CacheFilePath
        )
        aider @parms
    }
}

function Repair-ParameterTest {
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

        # Run Aider in non-interactive mode with auto-confirmation
        $params = @(
            "--message", $cmdPrompt,
            "--file", $filename,
            "--yes-always",
            "--no-stream",
            "--model", $Model
        )
        aider @params
    }
    <#
        # <_>
        # It "has the required parameter: <$_>" -ForEach $params { # 2
        # It "has the required parameter: $_" # 25
        # It "has all the required parameters" -ForEach $requiredParameters {
        # Copy-DbaDbViewData.Tests.ps1: $params | ForEach-Object {
        # It "has the required parameter: SqlInstance" -ForEach $params { 7
        # It "has the required parameter: $_" -ForEach $params {
        # It "has the required parameter: $_" -ForEach $params {
        # It "has the required parameter: SqlInstance" -ForEach $params {
        # It "has the required parameter: $_" -ForEach $params {
        # It "has the required parameter: $_" -ForEach $params {
        # It "has the required parameter: $_" -ForEach $params {

        <#
            BeforeDiscovery {
                [object[]]$params = (Get-Command Copy-DbaDatabase).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            }

        #>
    #>
}