[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["job"] = @{ }

$ScriptBlock = {
	param (
		$commandName,
		$parameterName,
		$wordToComplete,
		$commandAst,
		$fakeBoundParameter
	)
	
	$start = Get-Date
	[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["job"].LastExecution = $start
	
	$server = $fakeBoundParameter['SqlInstance']
	
	if (-not $server) {
		$server = $fakeBoundParameter['Source']
	}
	
	if (-not $server) {
		$server = $fakeBoundParameter['ComputerName']
	}
	
	if (-not $server) { return }
	
	try {
		[DbaInstanceParameter]$parServer = $server | Select-Object -First 1
	}
	catch {
		[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["job"].LastDuration = (Get-Date) - $start
		return
	}
	
	if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["job"][$parServer.FullSmoName.ToLower()]) {
		foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["job"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*")) {
			New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
		}
		[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["job"].LastDuration = (Get-Date) - $start
		return
	}
	
	try {
		$serverObject = Connect-SqlInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
		foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["job"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*")) {
			New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
		}
		[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["job"].LastDuration = (Get-Date) - $start
		return
	}
	catch {
		[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["job"].LastDuration = (Get-Date) - $start
		return
	}
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name Job