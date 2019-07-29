#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]) {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @()
}
#endregion Initialize Cache

#region Tepp Data return
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] | Where-DbaObject -Like "$wordToComplete*")) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name "sqlinstance"
#endregion Tepp Data return