param (
    [int]$First = 1000,
    [int]$Skip = 0
)
# Full prompt path
if (-not (Get-Module dbatools.library -ListAvailable)) {
    Write-Warning "dbatools.library not found, installing"
    Install-Module dbatools.library -Scope CurrentUser -Force
}
Import-Module /workspace/dbatools.psm1

$promptTemplate = Get-Content /workspace/.aider/prompts/template.md
$commands = Get-Command -Module dbatools -Type Function, Cmdlet | Select-Object -First $First -Skip $Skip

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

    $cmdPrompt = $promptTemplate -replace "--CMDNAME--", $command.Name
    $parameters = $command.Parameters.Values

    foreach ($param in $parameters) {
        $paramName = $param.Name
        $paramType = $param.ParameterType.Name

        if ($param.IsMandatory) {
            $isMandatory = "is"
        } else {
            $isMandatory = "is not"
        }

        $cmdPrompt += "$paramName is $paramType and $isMandatory mandatory"
    }
    $cmdprompt = $cmdPrompt -join "`n"

    # Run Aider in non-interactive mode with auto-confirmation
    aider --message "$cmdPrompt" --file $filename --yes --no-stream --cache-prompts --read /workspace/.aider/prompts/conventions.md
}