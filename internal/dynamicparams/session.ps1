#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"]) {
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"] = @{ }
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
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["session"].LastExecution = $start

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
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["session"].LastDuration = (Get-Date) - $start
		return
	}

	if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"][$parServer.FullSmoName.ToLower()])
	{
		foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
		{
			New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
		}
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["session"].LastDuration = (Get-Date) - $start
		return
	}

	try
	{
		$serverObject = Connect-SqlInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
		foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
		{
			New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
		}
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["session"].LastDuration = (Get-Date) - $start
		return
	}
	catch
	{
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["session"].LastDuration = (Get-Date) - $start
		return
	}
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name session
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

	$SqlConn = $server.ConnectionContext.SqlConnectionObject
	$SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
	$XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
	$xesessions = $XEStore.sessions
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["session"][$FullSmoName] = $xesessions.Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache
