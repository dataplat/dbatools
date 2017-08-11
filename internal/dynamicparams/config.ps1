#region Tepp Data return: FullName
$ScriptBlock = {
	param (
		$commandName,
		
		$parameterName,
		
		$wordToComplete,
		
		$commandAst,
		
		$fakeBoundParameter
	)
	
	$start = Get-Date
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["config"].LastExecution = $start
	
	foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.Config]::Cfg.Keys | Where-DbaObject -Like "$wordToComplete*" | Sort-Object)) {
		New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
	}
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["config"].LastDuration = (Get-Date) - $start	
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name config
#endregion Tepp Data return: FullName

#region Tepp Data return: Name
$ScriptBlock = {
	param (
		$commandName,
		
		$parameterName,
		
		$wordToComplete,
		
		$commandAst,
		
		$fakeBoundParameter
	)
	
	$start = Get-Date
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["configname"].LastExecution = $start
	
	foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.Config]::Cfg.Values.Name | Select-Object -Unique | Where-DbaObject -Like "$wordToComplete*" | Sort-Object)) {
		New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
	}
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["configname"].LastDuration = (Get-Date) - $start
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name configname
#endregion Tepp Data return: Name

#region Tepp Data return: Module
$ScriptBlock = {
	param (
		$commandName,
		
		$parameterName,
		
		$wordToComplete,
		
		$commandAst,
		
		$fakeBoundParameter
	)
	
	$start = Get-Date
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["configmodule"].LastExecution = $start
	
	foreach ($name in ([Sqlcollaborative.Dbatools.Configuration.Config]::Cfg.Values.Module | Select-Object -Unique | Where-DbaObject -Like "$wordToComplete*" | Sort-Object )) {
		New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
	}
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts["configmodule"].LastDuration = (Get-Date) - $start
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name configmodule
#endregion Tepp Data return: Module