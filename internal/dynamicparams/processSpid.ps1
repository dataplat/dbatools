$scriptBlock = {
	param (
		$commandName,
		
		$parameterName,
		
		$wordToComplete,
		
		$commandAst,
		
		$fakeBoundParameter
	)
	
	$start = Get-Date
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["processspid"].LastExecution = $start
	
	$server = $fakeBoundParameter['SqlInstance']
	if (-not $server) {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["processspid"].LastDuration = (Get-Date) - $start
		return
	}
	$sqlCredential = $fakeBoundParameter['SqlCredential']
	
	try {
		if ($sqlCredential) { $instance = Connect-DbaSqlServer -SqlInstance $server -ErrorAction Stop }
		else { $instance = Connect-DbaSqlServer -SqlInstance $server -ErrorAction Stop }
		
		$instance.EnumProcesses().Spid | Select-Object -Unique | Where-DbaObject -Like "$wordToComplete*" | ForEach-Object {
			if (-not ([string]::IsNullOrWhiteSpace($_))) { New-DbaTeppCompletionResult -CompletionText $_ -ToolTip $_ }
		}
	}
	catch {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["processspid"].LastDuration = (Get-Date) - $start
		return
	}
	finally {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["processspid"].LastDuration = (Get-Date) - $start
	}
}

Register-DbaTeppScriptblock -ScriptBlock $scriptBlock -Name processspid