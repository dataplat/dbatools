# Full prompt path
if (-not (Get-Module dbatools.library -ListAvailable)) {
    Install-Module dbatools.library -Scope CurrentUser -Force
}
Import-Module /workspace/dbatools.psm1

$promptTemplate = Get-Content /workspace/.aider/prompts/template.md
$commands = Get-Command -Module dbatools | Select-Object -First 1

foreach ($command in $commands) {
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
    aider --message "$cmdPrompt" "$($command.Name).Tests.ps1" --yes
}