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