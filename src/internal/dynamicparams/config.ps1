#region Tepp Data return: FullName
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object { -not $_.Hidden -and ($_.FullName -Like "$wordToComplete*") } | Select-Object -ExpandProperty FullName | Sort-Object)) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name config
#endregion Tepp Data return: FullName

#region Tepp Data return: Name
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    $moduleName = "*"
    if ($fakeBoundParameter.Module) { $moduleName = $fakeBoundParameter.Module }

    foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object { (-not $_.Hidden) -and ($_.Name -Like "$wordToComplete*") -and ($_.Module -like $moduleName) } | Select-Object -ExpandProperty Name | Sort-Object)) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name config_name
#endregion Tepp Data return: Name

#region Tepp Data return: Module
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values.Module | Select-Object -Unique | Where-DbaObject -Like "$wordToComplete*" | Sort-Object )) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name configmodule
#endregion Tepp Data return: Module