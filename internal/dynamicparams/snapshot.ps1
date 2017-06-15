#region Initialize Cache
if (-not [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"]) {
	[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"] = @{ }
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
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["snapshot"].LastExecution = $start
	
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
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["snapshot"].LastDuration = (Get-Date) - $start
        return
    }
    
    if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"][$parServer.FullSmoName.ToLower()])
    {
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["snapshot"].LastDuration = (Get-Date) - $start
        return
    }
    
    try
    {
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["snapshot"].LastDuration = (Get-Date) - $start
        return
    }
    catch
    {
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["snapshot"].LastDuration = (Get-Date) - $start
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name snapshot
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {
	if ($PSVersionTable.PSVersion.Major -ge 4) { [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"][$FullSmoName] = $server.Databases.Where({ $_.IsDatabaseSnapShot }).Name }
	else { [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["snapshot"][$FullSmoName] = ($server.Databases | Where-Object IsDatabaseSnapShot).Name }
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache