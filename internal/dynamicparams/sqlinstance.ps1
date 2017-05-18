[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @()

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