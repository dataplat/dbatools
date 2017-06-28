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
    
    $start = Get-Date
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["sqlinstance"].LastExecution = $start
    
    foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] | Where-DbaObject -Like "$wordToComplete*"))
    {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["sqlinstance"].LastDuration = (Get-Date) - $start
}
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name "sqlinstance"
#endregion Tepp Data return
