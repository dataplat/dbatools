#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["powerplan"]) {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["powerplan"] = @()
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


    foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["powerplan"] | Where-DbaObject -Like "$wordToComplete*")) {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
}
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name "powerplan"
#endregion Tepp Data return

#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["powerplan"]) {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["powerplan"] = 'High Performance', 'Balanced', 'Power saver'
}
#endregion Initialize Cache
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name powerplan
#endregion Tepp Data return