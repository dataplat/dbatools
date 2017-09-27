#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"]) {
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"] = @{ }
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
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["mailaccount"].LastExecution = $start
	
	$server = $fakeBoundParameter['SqlInstance']
	
	if (-not $server) {
		$server = $fakeBoundParameter['Source']
	}
	
	if (-not $server) {
		$server = $fakeBoundParameter['ComputerName']
	}
	
	if (-not $server) { return }
	
    try
    {
        [DbaInstanceParameter]$parServer = $server | Select-Object -First 1
    }
    catch
    {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["mailaccount"].LastDuration = (Get-Date) - $start
        return
    }
    
    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLower()])
    {
        foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["mailaccount"].LastDuration = (Get-Date) - $start
        return
    }
    
    try
    {
        $serverObject = Connect-SqlInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["mailaccount"].LastDuration = (Get-Date) - $start
        return
    }
    catch
    {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["mailaccount"].LastDuration = (Get-Date) - $start
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name MailAccount
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$FullSmoName] = $server.Mail.Accounts.Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
