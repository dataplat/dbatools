#region Initialize Cache
if (-not [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]) {
	[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @()
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
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["sqlinstance"].LastExecution = $start
    
    foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] | Where-DbaObject -Like "$wordToComplete*"))
    {
        New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
    }
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["sqlinstance"].LastDuration = (Get-Date) - $start
}
Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name "sqlinstance"
#endregion Tepp Data return