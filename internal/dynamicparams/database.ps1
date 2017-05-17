[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"] = @{ }

$ScriptBlock = {
    param (
        $commandName,
        
        $parameterName,
        
        $wordToComplete,
        
        $commandAst,
        
        $fakeBoundParameter
    )
    
    $start = Get-Date
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastExecution = $start
	
	$server = $fakeBoundParameter['SqlInstance']
	
	if (-not $server) {
		$server = $fakeBoundParameter['Source']
	}
	
	if (-not $server) {
		$server = $fakeBoundParameter['SqlServer']
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
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    
    if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()])
    {
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    
    try
    {
        $serverObject = Connect-SqlServer -SqlServer $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    catch
    {
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name Database

$commands = @('Backup-DbaDatabase',
	'Copy-DbaDatabase',
	'Expand-DbaTLogResponsibly',
	'Export-DbaExecutionPlan',
	'Export-DbaLogin',
	'Export-DbaUser',
	'Find-DbaDatabaseGrowthEvent',
	'Find-DbaStoredProcedure',
	'Find-DbaUnusedIndex',
	'Get-DbaBackupHistory',
	'Get-DbaDatabase',
	'Get-DbaDatabaseEncryption',
	'Get-DbaDatabaseFile',
	'Get-DbaDatabaseFreespace',
	'Get-DbaDatabaseState',
	'Get-DbaEstimatedCompletionTime',
	'Get-DbaExecutionPlan',
	'Get-DbaHelpIndex',
	'Get-DbaLastBackup',
	'Get-DbaLastGoodCheckDb',
	'Get-DbaPermission',
	'Get-DbaQueryExecutionTime',
	'Get-DbaQueryStoreConfig',
	'Get-DbaRestoreHistory',
	'Get-DbaRoleMember',
	'Get-DbaSchemaChangeHistory',
	'Get-DbaTable',
	'Get-DbaTrigger',
	'Invoke-DbaDatabaseShrink',
	'Measure-DbaBackupThroughput',
	'New-DbaDatabaseSnapshot',
	'Remove-DbaDatabase',
	'Remove-DbaDatabaseSafely',
	'Remove-DbaOrphanUser',
	'Repair-DbaOrphanUser',
	'Set-DbaDatabaseOwner',
	'Set-DbaDatabaseState',
	'Set-DbaMaxDop',
	'Set-DbaQueryStoreConfig',
	'Test-DbaDatabaseCollation',
	'Test-DbaDatabaseCompatibility',
	'Test-DbaDatabaseOwner',
	'Test-DbaFullRecoveryModel',
	'Test-DbaIdentityUsage',
	'Test-DbaLastBackup',
	'Test-DbaMigrationConstraint',
	'Test-DbaVirtualLogFile'
)

if ($TEPP) {
	TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $commands -ParameterName Database -ScriptBlock $ScriptBlock
	TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $commands -ParameterName Exclude -ScriptBlock $ScriptBlock
}
else {
	Register-ArgumentCompleter -CommandName $commands -ParameterName Database -ScriptBlock $ScriptBlock
	Register-ArgumentCompleter -CommandName $commands -ParameterName Exclude -ScriptBlock $ScriptBlock
}