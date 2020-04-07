#region Tepp Data return: Path
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    foreach ($name in (([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object FullName -like "path.managed.*").FullName -replace '^path\.managed\.')) {
        if ($name -notlike "$wordToComplete*") { continue }
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name path
#endregion Tepp Data return: Path