# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
	# run on scenario 2008R2
	"2008R2" = @(
		'Add-DbaComputerCertificate',
		'Connect-DbaSqlServer',
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
		'Get-DbaSqlService',
		'Invoke-DbaCycleErrorLog',
		'Invoke-DbaDiagnosticQuery',
		'Mount-DbaDatabase',
		'Remove-DbaDatabase',
		'Restore-DbaDatabase',
		'Set-DbaSpConfigure',
		'Test-DbaIdentityUsage'
	)
	# run on scenario 2016
	"2016" = @(
		'Dismount-DbaDatabase',
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
	# do not run on appveyor
	"appveyor_disabled" = @(
		'Get-DbaDatabaseState'
	)
	# do not run everywhere
	"disabled" = @()
}