# Not supporting the provider path at this time 2/28/2017 - 63ms
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\"))
{
	Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
	Write-Warning "Going to continue loading anyway, but expect issues."
}

<#

	Attempt to load all versions of SMO from vNext to 2005 - this is why RequiredAssemblies can't be used.

	Attempt to load all assemblies that will be needed in the module. 

	Not all versions support supporting assemblies, so ignore and let the command catch it.

	This takes about 11-50ms on a newer machine.

#>

$smoversions = "13.0.0.0", "12.0.0.0", "11.0.0.0", "10.0.0.0", "14.0.0.0", "9.0.242.0", "9.0.0.0"

foreach ($smoversion in $smoversions)
{
	try
	{
		Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
		$smoadded = $true
	}
	catch
	{
		$smoadded = $false
	}
	
	if ($smoadded -eq $true) { break }
}

if ($smoadded -eq $false) { throw "Can't load SMO assemblies. You must have SQL Server Management Studio installed to proceed." }

$assemblies = "Management.Common", "Dmf", "Instapi", "SqlWmiManagement", "ConnectionInfo", "SmoExtended", "SqlTDiagM", "Management.Utility",
"SString", "Management.RegisteredServers", "Management.Sdk.Sfc", "SqlEnum", "RegSvrEnum", "WmiEnum", "ServiceBrokerEnum", "Management.XEvent",
"ConnectionInfoExtended", "Management.Collector", "Management.CollectorEnum", "Management.Dac", "Management.DacEnum", "Management.IntegrationServices"

foreach ($assembly in $assemblies)
{
	try
	{
		Add-Type -AssemblyName "Microsoft.SqlServer.$assembly, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
	}
	catch
	{
		Write-Verbose "$assembly not loaded for version $smoversion"
	}
}

<# 

	Do the rest of the loading 

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports - 141ms
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\bin\library.ps1"))), $null, $null)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\bin\typealiases.ps1"))), $null, $null)

# All internal functions privately available within the toolset - 221ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

#region Finally register autocompletion - 32ms
# Test whether we have Tab Expansion Plus available (used in dynamicparams scripts ran below)
if (Get-Command TabExpansionPlusPlus\Register-ArgumentCompleter -ErrorAction Ignore)
{
	$script:TEPP = $true
}
else
{
	$script:TEPP = $false
}

# dynamic params - 136ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\dynamicparams\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}
#endregion Finally register autocompletion

# All exported functions - 600ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\optional\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

# Process TEPP parameters
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\scripts\insertTepp.ps1"))), $null, $null)

# Load configuration system
# Should always go next to last
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\configurations\configuration.ps1"))), $null, $null)

# Load scripts that must be individually run at the end - 30ms #
#--------------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\scripts\logfilescript.ps1"))), $null, $null)

# Start the tepp asynchronous update system (requires the configuration system up and running)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\scripts\updateTeppAsync.ps1"))), $null, $null)

# I renamed this function to be more accurate - 1ms
Set-Alias -Scope Global -Name Reset-SqlSaPassword -Value Reset-SqlAdmin
Set-Alias -Scope Global -Name Copy-SqlUserDefinedMessage -Value Copy-SqlCustomError
Set-Alias -Scope Global -Name Copy-SqlJobServer -Value Copy-SqlServerAgent
Set-Alias -Scope Global -Name Restore-HallengrenBackup -Value Restore-SqlBackupFromDirectory
Set-Alias -Scope Global -Name Show-SqlMigrationConstraint -Value Test-SqlMigrationConstraint
Set-Alias -Scope Global -Name Test-SqlDiskAllocation -Value Test-DbaDiskAllocation
Set-Alias -Scope Global -Name Get-DiskSpace -Value Get-DbaDiskSpace
Set-Alias -Scope Global -Name Get-SqlMaxMemory -Value Get-DbaMaxMemory
Set-Alias -Scope Global -Name Set-SqlMaxMemory -Value Set-DbaMaxMemory
Set-Alias -Scope Global -Name Install-SqlWhoIsActive -Value Install-DbaWhoIsActive
Set-Alias -Scope Global -Name Show-SqlWhoIsActive -Value Invoke-DbaWhoIsActive
Set-Alias -Scope Global -Name Copy-SqlAgentCategory -Value Copy-DbaAgentCategory
Set-Alias -Scope Global -Name Copy-SqlAlert -Value Copy-DbaAgentAlert
Set-Alias -Scope Global -Name Copy-SqlAudit -Value Copy-DbaAudit
Set-Alias -Scope Global -Name Copy-SqlAuditSpecification -Value Copy-DbaAuditSpecification
Set-Alias -Scope Global -Name Copy-SqlBackupDevice -Value Copy-DbaBackupDevice
Set-Alias -Scope Global -Name Copy-SqlCentralManagementServer -Value Copy-DbaCentralManagementServer
Set-Alias -Scope Global -Name Copy-SqlCredential -Value Copy-DbaCredential
Set-Alias -Scope Global -Name Copy-SqlCustomError -Value Copy-DbaCustomError
Set-Alias -Scope Global -Name Copy-SqlDatabase -Value Copy-DbaDatabase
Set-Alias -Scope Global -Name Copy-SqlDatabaseAssembly -Value Copy-DbaDatabaseAssembly
Set-Alias -Scope Global -Name Copy-SqlDatabaseMail -Value Copy-DbaDatabaseMail
Set-Alias -Scope Global -Name Copy-SqlDataCollector -Value Copy-DbaDataCollector
Set-Alias -Scope Global -Name Copy-SqlEndpoint -Value Copy-DbaEndpoint
Set-Alias -Scope Global -Name Copy-SqlExtendedEvent -Value Copy-DbaExtendedEvent
Set-Alias -Scope Global -Name Copy-SqlJob -Value Copy-DbaJob
Set-Alias -Scope Global -Name Copy-SqlLinkedServer -Value Copy-DbaLinkedServer
Set-Alias -Scope Global -Name Copy-SqlLogin -Value Copy-DbaLogin
Set-Alias -Scope Global -Name Copy-SqlOperator -Value Copy-DbaOperator
Set-Alias -Scope Global -Name Copy-SqlPolicyManagement -Value Copy-DbaPolicyManagement
Set-Alias -Scope Global -Name Copy-SqlProxyAccount -Value Copy-DbaProxyAccount
Set-Alias -Scope Global -Name Copy-SqlResourceGovernor -Value Copy-DbaResourceGovernor
Set-Alias -Scope Global -Name Copy-SqlServerAgent -Value Copy-DbaServerAgent
Set-Alias -Scope Global -Name Copy-SqlServerRole -Value Copy-DbaServerRole
Set-Alias -Scope Global -Name Copy-SqlServerTrigger -Value Copy-DbaServerTrigger
Set-Alias -Scope Global -Name Copy-SqlSharedSchedule -Value Copy-DbaSharedSchedule
Set-Alias -Scope Global -Name Copy-SqlSpConfigure -Value Copy-DbaSpConfigure
Set-Alias -Scope Global -Name Copy-SqlSsisCatalog -Value Copy-DbaSsisCatalog
Set-Alias -Scope Global -Name Copy-SqlSysDbUserObjects -Value Copy-DbaSysDbUserObjects
Set-Alias -Scope Global -Name Expand-SqlTLogResponsibly -Value Expand-DbaTLogResponsibly
Set-Alias -Scope Global -Name Export-SqlLogin -Value Export-DbaLogin
Set-Alias -Scope Global -Name Export-SqlSpConfigure -Value Export-DbaSpConfigure
Set-Alias -Scope Global -Name Export-SqlUser -Value Export-DbaUser
Set-Alias -Scope Global -Name Find-SqlDuplicateIndex -Value Find-DbaDuplicateIndex
Set-Alias -Scope Global -Name Find-SqlUnusedIndex -Value Find-DbaUnusedIndex
Set-Alias -Scope Global -Name Get-SqlRegisteredServerName -Value Get-DbaRegisteredServerName
Set-Alias -Scope Global -Name Get-SqlServerKey -Value Get-DbaSqlProductKey
Set-Alias -Scope Global -Name Import-SqlSpConfigure -Value Import-DbaSpConfigure
Set-Alias -Scope Global -Name Invoke-Sqlcmd2 -Value Invoke-DbaSqlcmd
Set-Alias -Scope Global -Name Remove-SqlDatabaseSafely -Value Remove-DbaDatabaseSafely
Set-Alias -Scope Global -Name Remove-SqlOrphanUser -Value Remove-DbaOrphanUser
Set-Alias -Scope Global -Name Repair-SqlOrphanUser -Value Repair-DbaOrphanUser
Set-Alias -Scope Global -Name Reset-SqlAdmin -Value Reset-DbaAdmin
Set-Alias -Scope Global -Name Restore-SqlBackupFromDirectory -Value Restore-DbaBackupFromDirectory
Set-Alias -Scope Global -Name Set-SqlTempDbConfiguration -Value Set-DbaTempDbConfiguration
Set-Alias -Scope Global -Name Show-SqlDatabaseList -Value Show-DbaDatabaseList
Set-Alias -Scope Global -Name Show-SqlServerFileSystem -Value Show-DbaServerFileSystem
Set-Alias -Scope Global -Name Start-SqlMigration -Value Start-DbaMigration
Set-Alias -Scope Global -Name Sync-SqlLoginPermissions -Value Sync-DbaLoginPermissions
Set-Alias -Scope Global -Name Test-SqlConnection -Value Test-DbaConnection
Set-Alias -Scope Global -Name Test-SqlMigrationConstraint -Value Test-DbaMigrationConstraint
Set-Alias -Scope Global -Name Test-SqlNetworkLatency -Value Test-DbaNetworkLatency
Set-Alias -Scope Global -Name Test-SqlPath -Value Test-DbaPath
Set-Alias -Scope Global -Name Test-SqlTempDbConfiguration -Value Test-DbaTempDbConfiguration
Set-Alias -Scope Global -Name Watch-SqlDbLogin -Value Watch-DbaDbLogin
