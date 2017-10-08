# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
	# run on scenario 2008R2
	"2008R2"            = @(
		'Add-DbaComputerCertificate',
		'Connect-DbaInstance',
		'Get-DbaAgentJobs',
		'Get-DbaAgentJobOutputFile',
		'Get-DbaBackupHistory',
		'Get-DbaComputerSystem',
		'Get-DbaDatabase',
		'Get-DbaDatabaseEncryption',
		'Get-DbaDbStoredProcedure',
		'Get-DbaLogin',
		'Get-DbaOperatingSystem',
		'Get-DbaProcess',
		'Get-DbaRegisteredServerName',
		'Get-DbaSchemaChangeHistory',
		'Get-DbaSpConfigure',
		'Get-DbaSqlLog',
		'Get-DbaSqlModule',
		'Invoke-DbaCycleErrorLog',
		'Invoke-DbaDiagnosticQuery',
		'Mount-DbaDatabase',
		'Remove-DbaDatabase -Confirm:$false',
		'Restore-DbaDatabase',
		'Set-DbaSpConfigure',
		'Test-DbaIdentityUsage'
	)
	# run on scenario 2016
	"2016"              = @(
		'Get-DbaAgDatabase',
		'Get-DbaAgHadr',
		'Get-DbaAgReplica',
		'Get-DbaAvailabilityGroup',
		'Get-DbaDatabaseSnapshot',
		'Get-DbaFile',
		'Get-DbaLastBackup',
		'Get-DbaRegisteredServersStore',
		'Get-DbaTraceFlag',
		'Install-DbaMaintenanceSolution',
		'Measure-DbaBackupThroughput',
		'New-DbaAgentJob',
		'New-DbaAgentJobStep',
		'New-DbaDatabaseSnapshot',
		'New-DbaSsisCatalog',
		'Remove-DbaDatabaseSnapshot',
		'Restore-DbaFromDatabaseSnapshot',
		'Test-DbaDbCompression',
		'Test-DbaLastBackup'
	)
	#run on scenario 2016_service - SQL Server service tests that might disrupt other tests
	"2016_service" = @(
		'Start-DbaSqlService',
		'Stop-DbaSqlService',
		'Restart-DbaSqlService',
		'Get-DbaSqlService',
		'Update-DbaSqlServiceAccount'
	)
	# do not run on appveyor
	"appveyor_disabled" = @(
		'Get-DbaDatabaseState',
		'Dismount-DbaDatabase'
	)
	
	# do not run everywhere
	"disabled"          = @()
}
