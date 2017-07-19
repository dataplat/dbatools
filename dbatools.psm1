# Not supporting the provider path at this time 2/28/2017 - 63ms
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\"))
{
	Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
	Write-Warning "Going to continue loading anyway, but expect issues."
}

$script:PSModuleRoot = $PSScriptRoot

# Detect whether at some level dotsourcing was enforced
$script:doDotSource = $false
if ($dbatools_dotsourcemodule) { $script:doDotSource = $true }
if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name "DoDotSource" -ErrorAction Ignore).DoDotSource) { $script:doDotSource = $true }
if ((Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name "DoDotSource" -ErrorAction Ignore).DoDotSource) { $script:doDotSource = $true }


if (([environment]::OSVersion.Version).Major -gt 6) {
	Get-ChildItem -Path "$script:PSModuleRoot\bin\*.dll" | Unblock-File -ErrorAction SilentlyContinue
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Smo.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Dmf.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.SqlWmiManagement.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.ConnectionInfo.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.SmoExtended.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.RegisteredServers.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.Sdk.Sfc.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.SqlEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.RegSvrEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.WmiEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.ServiceBrokerEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.Collector.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.CollectorEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.Utility.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.UtilityEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.HadrDMF.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.XEvent.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.XEventEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.XEventDbScoped.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.XEventDbScopedEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.XEventEnum.dll"
	Add-Type -Path "$script:PSModuleRoot\bin\Microsoft.SqlServer.Management.Collector.dll"
}
else {
<#
	Attempt to load all versions of SMO from vNext to 2005 - this is why RequiredAssemblies can't be used.
	Attempt to load all assemblies that will be needed in the module. 
	Not all versions support supporting assemblies, so ignore and let the command catch it.
	This takes about 11-50ms on a newer machine.
#>
	Write-Verbose "Had to failback"
	$smoversions = "14.0.0.0", "13.0.0.0", "12.0.0.0", "11.0.0.0", "10.0.0.0", "9.0.242.0", "9.0.0.0"
	
	foreach ($smoversion in $smoversions) {
		try {
			Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
			$smoadded = $true
		}
		catch {
			$smoadded = $false
		}
		
		if ($smoadded -eq $true) { break }
	}
	
	if ($smoadded -eq $false) { throw "Can't load SMO assemblies. You must have SQL Server Management Studio installed to proceed." }
	
	$assemblies = "Management.Common", "Dmf", "Instapi", "SqlWmiManagement", "ConnectionInfo", "SmoExtended", "SqlTDiagM", "Management.Utility",
	"SString", "Management.RegisteredServers", "Management.Sdk.Sfc", "SqlEnum", "RegSvrEnum", "WmiEnum", "ServiceBrokerEnum", "Management.XEvent",
	"ConnectionInfoExtended", "Management.Collector", "Management.CollectorEnum", "Management.Dac", "Management.DacEnum", "Management.IntegrationServices"
	
	foreach ($assembly in $assemblies) {
		try {
			Add-Type -AssemblyName "Microsoft.SqlServer.$assembly, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
		}
		catch {
			# Don't care
		}
	}
}


<# 

	Do the rest of the loading 

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports - 141ms
if ($script:doDotSource) {
	. "$script:PSModuleRoot\bin\library.ps1"
	. "$script:PSModuleRoot\bin\typealiases.ps1"
}
else {
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\bin\library.ps1"))), $null, $null)
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\bin\typealiases.ps1"))), $null, $null)
}

# All internal functions privately available within the toolset - 221ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\internal\*.ps1")) {
	if ($script:doDotSource) { . $function.FullName }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null) }
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
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\dynamicparams\*.ps1")) {
	if ($script:doDotSource) { . $function.FullName }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null) }
}
#endregion Finally register autocompletion

# All exported functions - 600ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\functions\*.ps1")) {
	if ($script:doDotSource) { . $function.FullName }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null) }
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\optional\*.ps1")) {
	if ($script:doDotSource) { . $function.FullName }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null) }
}

# Process TEPP parameters
if ($script:doDotSource) { . "$script:PSModuleRoot\internal\scripts\insertTepp.ps1" }
else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\internal\scripts\insertTepp.ps1"))), $null, $null) }

# Load configuration system
# Should always go next to last
if ($script:doDotSource) { . "$script:PSModuleRoot\internal\configurations\configuration.ps1" }
else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\internal\configurations\configuration.ps1"))), $null, $null) }

# Load scripts that must be individually run at the end - 30ms #
#--------------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
if ($script:doDotSource) { . "$script:PSModuleRoot\internal\scripts\logfilescript.ps1" }
else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\internal\scripts\logfilescript.ps1"))), $null, $null) }

# Start the tepp asynchronous update system (requires the configuration system up and running)
if ($script:doDotSource) { . "$script:PSModuleRoot\internal\scripts\updateTeppAsync.ps1" }
else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$script:PSModuleRoot\internal\scripts\updateTeppAsync.ps1"))), $null, $null) }

# I renamed this function to be more accurate - 1ms
if (-not (Test-Path Alias:Copy-SqlAgentCategory)) { Set-Alias -Scope Global -Name Copy-SqlAgentCategory -Value Copy-DbaAgentCategory }
if (-not (Test-Path Alias:Copy-SqlAlert)) { Set-Alias -Scope Global -Name Copy-SqlAlert -Value Copy-DbaAgentAlert }
if (-not (Test-Path Alias:Copy-SqlAudit)) { Set-Alias -Scope Global -Name Copy-SqlAudit -Value Copy-DbaAudit }
if (-not (Test-Path Alias:Copy-SqlAuditSpecification)) { Set-Alias -Scope Global -Name Copy-SqlAuditSpecification -Value Copy-DbaAuditSpecification }
if (-not (Test-Path Alias:Copy-SqlBackupDevice)) { Set-Alias -Scope Global -Name Copy-SqlBackupDevice -Value Copy-DbaBackupDevice }
if (-not (Test-Path Alias:Copy-SqlCentralManagementServer)) { Set-Alias -Scope Global -Name Copy-SqlCentralManagementServer -Value Copy-DbaCentralManagementServer }
if (-not (Test-Path Alias:Copy-SqlCredential)) { Set-Alias -Scope Global -Name Copy-SqlCredential -Value Copy-DbaCredential }
if (-not (Test-Path Alias:Copy-SqlCustomError)) { Set-Alias -Scope Global -Name Copy-SqlCustomError -Value Copy-DbaCustomError }
if (-not (Test-Path Alias:Copy-SqlDatabase)) { Set-Alias -Scope Global -Name Copy-SqlDatabase -Value Copy-DbaDatabase }
if (-not (Test-Path Alias:Copy-SqlDatabaseAssembly)) { Set-Alias -Scope Global -Name Copy-SqlDatabaseAssembly -Value Copy-DbaDatabaseAssembly }
if (-not (Test-Path Alias:Copy-SqlDatabaseMail)) { Set-Alias -Scope Global -Name Copy-SqlDatabaseMail -Value Copy-DbaDatabaseMail }
if (-not (Test-Path Alias:Copy-SqlDataCollector)) { Set-Alias -Scope Global -Name Copy-SqlDataCollector -Value Copy-DbaDataCollector }
if (-not (Test-Path Alias:Copy-SqlEndpoint)) { Set-Alias -Scope Global -Name Copy-SqlEndpoint -Value Copy-DbaEndpoint }
if (-not (Test-Path Alias:Copy-SqlExtendedEvent)) { Set-Alias -Scope Global -Name Copy-SqlExtendedEvent -Value Copy-DbaExtendedEvent }
if (-not (Test-Path Alias:Copy-SqlJob)) { Set-Alias -Scope Global -Name Copy-SqlJob -Value Copy-DbaJob }
if (-not (Test-Path Alias:Copy-SqlJobServer)) { Set-Alias -Scope Global -Name Copy-SqlJobServer -Value Copy-SqlServerAgent }
if (-not (Test-Path Alias:Copy-SqlLinkedServer)) { Set-Alias -Scope Global -Name Copy-SqlLinkedServer -Value Copy-DbaLinkedServer }
if (-not (Test-Path Alias:Copy-SqlLogin)) { Set-Alias -Scope Global -Name Copy-SqlLogin -Value Copy-DbaLogin }
if (-not (Test-Path Alias:Copy-SqlOperator)) { Set-Alias -Scope Global -Name Copy-SqlOperator -Value Copy-DbaOperator }
if (-not (Test-Path Alias:Copy-SqlPolicyManagement)) { Set-Alias -Scope Global -Name Copy-SqlPolicyManagement -Value Copy-DbaPolicyManagement }
if (-not (Test-Path Alias:Copy-SqlProxyAccount)) { Set-Alias -Scope Global -Name Copy-SqlProxyAccount -Value Copy-DbaProxyAccount }
if (-not (Test-Path Alias:Copy-SqlResourceGovernor)) { Set-Alias -Scope Global -Name Copy-SqlResourceGovernor -Value Copy-DbaResourceGovernor }
if (-not (Test-Path Alias:Copy-SqlServerAgent)) { Set-Alias -Scope Global -Name Copy-SqlServerAgent -Value Copy-DbaServerAgent }
if (-not (Test-Path Alias:Copy-SqlServerRole)) { Set-Alias -Scope Global -Name Copy-SqlServerRole -Value Copy-DbaServerRole }
if (-not (Test-Path Alias:Copy-SqlServerTrigger)) { Set-Alias -Scope Global -Name Copy-SqlServerTrigger -Value Copy-DbaServerTrigger }
if (-not (Test-Path Alias:Copy-SqlSharedSchedule)) { Set-Alias -Scope Global -Name Copy-SqlSharedSchedule -Value Copy-DbaSharedSchedule }
if (-not (Test-Path Alias:Copy-SqlSpConfigure)) { Set-Alias -Scope Global -Name Copy-SqlSpConfigure -Value Copy-DbaSpConfigure }
if (-not (Test-Path Alias:Copy-SqlSsisCatalog)) { Set-Alias -Scope Global -Name Copy-SqlSsisCatalog -Value Copy-DbaSsisCatalog }
if (-not (Test-Path Alias:Copy-SqlSysDbUserObjects)) { Set-Alias -Scope Global -Name Copy-SqlSysDbUserObjects -Value Copy-DbaSysDbUserObjects }
if (-not (Test-Path Alias:Copy-SqlUserDefinedMessage)) { Set-Alias -Scope Global -Name Copy-SqlUserDefinedMessage -Value Copy-SqlCustomError }
if (-not (Test-Path Alias:Expand-SqlTLogResponsibly)) { Set-Alias -Scope Global -Name Expand-SqlTLogResponsibly -Value Expand-DbaTLogResponsibly }
if (-not (Test-Path Alias:Export-SqlLogin)) { Set-Alias -Scope Global -Name Export-SqlLogin -Value Export-DbaLogin }
if (-not (Test-Path Alias:Export-SqlSpConfigure)) { Set-Alias -Scope Global -Name Export-SqlSpConfigure -Value Export-DbaSpConfigure }
if (-not (Test-Path Alias:Export-SqlUser)) { Set-Alias -Scope Global -Name Export-SqlUser -Value Export-DbaUser }
if (-not (Test-Path Alias:Find-SqlDuplicateIndex)) { Set-Alias -Scope Global -Name Find-SqlDuplicateIndex -Value Find-DbaDuplicateIndex }
if (-not (Test-Path Alias:Find-SqlUnusedIndex)) { Set-Alias -Scope Global -Name Find-SqlUnusedIndex -Value Find-DbaUnusedIndex }
if (-not (Test-Path Alias:Get-SqlMaxMemory)) { Set-Alias -Scope Global -Name Get-SqlMaxMemory -Value Get-DbaMaxMemory }
if (-not (Test-Path Alias:Get-SqlRegisteredServerName)) { Set-Alias -Scope Global -Name Get-SqlRegisteredServerName -Value Get-DbaRegisteredServerName }
if (-not (Test-Path Alias:Get-SqlServerKey)) { Set-Alias -Scope Global -Name Get-SqlServerKey -Value Get-DbaSqlProductKey }
if (-not (Test-Path Alias:Import-SqlSpConfigure)) { Set-Alias -Scope Global -Name Import-SqlSpConfigure -Value Import-DbaSpConfigure }
if (-not (Test-Path Alias:Install-SqlWhoIsActive)) { Set-Alias -Scope Global -Name Install-SqlWhoIsActive -Value Install-DbaWhoIsActive }
if (-not (Test-Path Alias:Invoke-Sqlcmd2)) { Set-Alias -Scope Global -Name Invoke-Sqlcmd2 -Value Invoke-DbaSqlcmd }
if (-not (Test-Path Alias:Remove-SqlDatabaseSafely)) { Set-Alias -Scope Global -Name Remove-SqlDatabaseSafely -Value Remove-DbaDatabaseSafely }
if (-not (Test-Path Alias:Remove-SqlOrphanUser)) { Set-Alias -Scope Global -Name Remove-SqlOrphanUser -Value Remove-DbaOrphanUser }
if (-not (Test-Path Alias:Repair-SqlOrphanUser)) { Set-Alias -Scope Global -Name Repair-SqlOrphanUser -Value Repair-DbaOrphanUser }
if (-not (Test-Path Alias:Reset-SqlAdmin)) { Set-Alias -Scope Global -Name Reset-SqlAdmin -Value Reset-DbaAdmin }
if (-not (Test-Path Alias:Reset-SqlSaPassword)) { Set-Alias -Scope Global -Name Reset-SqlSaPassword -Value Reset-SqlAdmin }
if (-not (Test-Path Alias:Restore-SqlBackupFromDirectory)) { Set-Alias -Scope Global -Name Restore-SqlBackupFromDirectory -Value Restore-DbaBackupFromDirectory }
if (-not (Test-Path Alias:Set-SqlMaxMemory)) { Set-Alias -Scope Global -Name Set-SqlMaxMemory -Value Set-DbaMaxMemory }
if (-not (Test-Path Alias:Set-SqlTempDbConfiguration)) { Set-Alias -Scope Global -Name Set-SqlTempDbConfiguration -Value Set-DbaTempDbConfiguration }
if (-not (Test-Path Alias:Show-SqlDatabaseList)) { Set-Alias -Scope Global -Name Show-SqlDatabaseList -Value Show-DbaDatabaseList }
if (-not (Test-Path Alias:Show-SqlMigrationConstraint)) { Set-Alias -Scope Global -Name Show-SqlMigrationConstraint -Value Test-SqlMigrationConstraint }
if (-not (Test-Path Alias:Show-SqlServerFileSystem)) { Set-Alias -Scope Global -Name Show-SqlServerFileSystem -Value Show-DbaServerFileSystem }
if (-not (Test-Path Alias:Show-SqlWhoIsActive)) { Set-Alias -Scope Global -Name Show-SqlWhoIsActive -Value Invoke-DbaWhoIsActive }
if (-not (Test-Path Alias:Start-SqlMigration)) { Set-Alias -Scope Global -Name Start-SqlMigration -Value Start-DbaMigration }
if (-not (Test-Path Alias:Sync-SqlLoginPermissions)) { Set-Alias -Scope Global -Name Sync-SqlLoginPermissions -Value Sync-DbaLoginPermissions }
if (-not (Test-Path Alias:Test-SqlConnection)) { Set-Alias -Scope Global -Name Test-SqlConnection -Value Test-DbaConnection }
if (-not (Test-Path Alias:Test-SqlDiskAllocation)) { Set-Alias -Scope Global -Name Test-SqlDiskAllocation -Value Test-DbaDiskAllocation }
if (-not (Test-Path Alias:Test-SqlMigrationConstraint)) { Set-Alias -Scope Global -Name Test-SqlMigrationConstraint -Value Test-DbaMigrationConstraint }
if (-not (Test-Path Alias:Test-SqlNetworkLatency)) { Set-Alias -Scope Global -Name Test-SqlNetworkLatency -Value Test-DbaNetworkLatency }
if (-not (Test-Path Alias:Test-SqlPath)) { Set-Alias -Scope Global -Name Test-SqlPath -Value Test-DbaPath }
if (-not (Test-Path Alias:Test-SqlTempDbConfiguration)) { Set-Alias -Scope Global -Name Test-SqlTempDbConfiguration -Value Test-DbaTempDbConfiguration }
if (-not (Test-Path Alias:Watch-SqlDbLogin)) { Set-Alias -Scope Global -Name Watch-SqlDbLogin -Value Watch-DbaDbLogin }
if (-not (Test-Path Alias:Get-DiskSpace)) { Set-Alias -Scope Global -Name Get-DiskSpace -Value Get-DbaDiskSpace }
if (-not (Test-Path Alias:Restore-HallengrenBackup)) { Set-Alias -Scope Global -Name Restore-HallengrenBackup -Value Restore-SqlBackupFromDirectory }
if (-not (Test-Path Alias:Get-DbaDatabaseFreeSpace)) { Set-Alias -Scope Global -Name Get-DbaDatabaseFreeSpace -Value Get-DbaDatabaseSpace }

# Leave forever
Set-Alias -Scope Global -Name Attach-DbaDatabase -Value Mount-DbaDatabase
Set-Alias -Scope Global -Name Detach-DbaDatabase -Value Dismount-DbaDatabase