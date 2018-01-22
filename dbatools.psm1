$start = Get-Date

#region Import helper functions
function Import-ModuleFile {
<#
	.SYNOPSIS
		Helps import dbatools files according to configuration
	
	.DESCRIPTION
		Helps import dbatools files according to configuration
		Always dotsource this function!
	
	.PARAMETER Path
		The full path to the file to import
	
	.EXAMPLE
		PS C:\> Import-ModuleFile -Path $function.FullName
	
		Imports the file stored at '$function.FullName'
#>
	[CmdletBinding()]
	Param (
		$Path
	)
	
	if ($script:doDotSource) { . $Path }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($Path))), $null, $null)}
}

function Write-ImportTime {
<#
	.SYNOPSIS
		Writes an entry to the import module time debug list
	
	.DESCRIPTION
		Writes an entry to the import module time debug list
	
	.PARAMETER Text
		The message to write
	
	.EXAMPLE
		PS C:\> Write-ImportTime -Text "Starting SMO Import"
	
		Adds the message "Starting SMO Import" to the debug list
#>
	[CmdletBinding()]
	Param (
		[string]$Text,
		
		$Timestamp = (Get-Date)
	)
	
	if ($dbatools_disableTimeMeasurements) { return }
	
	if (-not $script:dbatools_ImportPerformance) { $script:dbatools_ImportPerformance = @() }
	
	if (([System.Management.Automation.PSTypeName]'Sqlcollaborative.Dbatools.Configuration.Config').Type -eq $null) {
		$script:dbatools_ImportPerformance += New-Object PSObject -Property @{ Time = $timestamp; Action = $Text }
	}
	else {
		if ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Count -eq 0) {
			foreach ($entry in $script:dbatools_ImportPerformance) { [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add((New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($entry.Action, $entry.Time, ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId)))) }
		}
		
		[Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add((New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($Text, $timestamp, ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))))
	}
}

Write-ImportTime -Text "Start" -Timestamp $start
Write-ImportTime -Text "Loading import helper functions"
#endregion Import helper functions

# Not supporting the provider path at this time 2/28/2017 - 63ms
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\"))
{
	Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
	Write-Warning "Going to continue loading anyway, but expect issues."
}

Write-ImportTime -Text "Resolved path to not SQLSERVER PSDrive"

$script:PSModuleRoot = $PSScriptRoot

#region Import Defines
$dbatoolsSystemUserNode = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ErrorAction Ignore
$dbatoolsSystemSystemNode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ErrorAction Ignore

#region Dot Sourcing
# Detect whether at some level dotsourcing was enforced
$script:doDotSource = $false
if ($dbatools_dotsourcemodule) { $script:doDotSource = $true }
if ($dbatoolsSystemSystemNode.DoDotSource) { $script:doDotSource = $true }
if ($dbatoolsSystemUserNode.DoDotSource) { $script:doDotSource = $true }
#endregion Dot Sourcing

#region Strict Security Mode
$script:strictSecurityMode = $false
if ($dbatools_strictsecuritymode) { $script:strictSecurityMode = $true }
if ($dbatoolsSystemSystemNode.StrictSecurityMode) { $script:strictSecurityMode = $true }
if ($dbatoolsSystemUserNode.StrictSecurityMode) { $script:strictSecurityMode = $true }
#endregion Strict Security Mode

#region Always Compile
$script:alwaysBuildLibrary = $false
if ($dbatools_alwaysbuildlibrary) { $script:alwaysBuildLibrary = $true }
if ($dbatoolsSystemSystemNode.AlwaysBuildLibrary) { $script:alwaysBuildLibrary = $true }
if ($dbatoolsSystemUserNode.AlwaysBuildLibrary) { $script:alwaysBuildLibrary = $true }
#endregion Always Compile

#region Serial Import
$script:serialImport = $false
if ($dbatools_serialimport) { $script:serialImport = $true }
if ($dbatoolsSystemSystemNode.SerialImport) { $script:serialImport = $true }
if ($dbatoolsSystemUserNode.SerialImport) { $script:serialImport = $true }
#endregion Serial Import
Write-ImportTime -Text  "Validated defines"
#endregion Import Defines

Get-ChildItem -Path "$script:PSModuleRoot\bin\*.dll" -Recurse | Unblock-File -ErrorAction SilentlyContinue
Write-ImportTime -Text  "Unblocking Files"

if (([System.Management.Automation.PSTypeName]'Sqlcollaborative.Dbatools.Configuration.Config').Type -eq $null) {
	. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\smoLibraryImport.ps1"
	Write-ImportTime -Text "Starting import SMO libraries"
}

<# 

	Do the rest of the loading 

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports
. Import-ModuleFile "$script:PSModuleRoot\bin\library.ps1"
. Import-ModuleFile "$script:PSModuleRoot\bin\typealiases.ps1"
Write-ImportTime -Text "Loading dbatools library"

# Tell the library where the module is based, just in case
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase = $script:PSModuleRoot

# Load configuration system
# Should always go after library and path setting
if (-not ([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported))
{
	. Import-ModuleFile "$script:PSModuleRoot\internal\configurations\configuration.ps1"
	Write-ImportTime -Text "Configuration System"
}
if (-not ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath))
{
	[Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath = "$($env:AppData)\PowerShell\dbatools"
}

# All internal functions privately available within the toolset - 221ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\internal\*.ps1"))
{
	. Import-ModuleFile $function.FullName
}
Write-ImportTime -Text "Loading Internal Commands"

# All exported functions - 600ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\functions\*.ps1")) {
	. Import-ModuleFile $function.FullName
}
Write-ImportTime -Text "Loading Public Commands"

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\optional\*.ps1"))
{
	. Import-ModuleFile $function.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\insertTepp.ps1"
Write-ImportTime -Text "Loading TEPP"


# Load scripts that must be individually run at the end - 30ms #
#--------------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\logfilescript.ps1"
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\updateTeppAsync.ps1"
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\dbatools-maintenance.ps1"
Write-ImportTime -Text "Script: Maintenance"

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
if (-not (Test-Path Alias:Copy-SqlJob)) { Set-Alias -Scope Global -Name Copy-SqlJob -Value Copy-DbaAgentJob }
if (-not (Test-Path Alias:Copy-SqlJobServer)) { Set-Alias -Scope Global -Name Copy-SqlJobServer -Value Copy-SqlServerAgent }
if (-not (Test-Path Alias:Copy-SqlLinkedServer)) { Set-Alias -Scope Global -Name Copy-SqlLinkedServer -Value Copy-DbaLinkedServer }
if (-not (Test-Path Alias:Copy-SqlLogin)) { Set-Alias -Scope Global -Name Copy-SqlLogin -Value Copy-DbaLogin }
if (-not (Test-Path Alias:Copy-SqlOperator)) { Set-Alias -Scope Global -Name Copy-SqlOperator -Value Copy-DbaAgentOperator }
if (-not (Test-Path Alias:Copy-SqlPolicyManagement)) { Set-Alias -Scope Global -Name Copy-SqlPolicyManagement -Value Copy-DbaPolicyManagement }
if (-not (Test-Path Alias:Copy-SqlProxyAccount)) { Set-Alias -Scope Global -Name Copy-SqlProxyAccount -Value Copy-DbaAgentProxyAccount }
if (-not (Test-Path Alias:Copy-SqlResourceGovernor)) { Set-Alias -Scope Global -Name Copy-SqlResourceGovernor -Value Copy-DbaResourceGovernor }
if (-not (Test-Path Alias:Copy-SqlServerAgent)) { Set-Alias -Scope Global -Name Copy-SqlServerAgent -Value Copy-DbaServerAgent }
if (-not (Test-Path Alias:Copy-SqlServerRole)) { Set-Alias -Scope Global -Name Copy-SqlServerRole -Value Copy-DbaServerRole }
if (-not (Test-Path Alias:Copy-SqlServerTrigger)) { Set-Alias -Scope Global -Name Copy-SqlServerTrigger -Value Copy-DbaServerTrigger }
if (-not (Test-Path Alias:Copy-SqlSharedSchedule)) { Set-Alias -Scope Global -Name Copy-SqlSharedSchedule -Value Copy-DbaAgentSharedSchedule }
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
if (-not (Test-Path Alias:Get-SqlRegisteredServerName)) { Set-Alias -Scope Global -Name Get-SqlRegisteredServerName -Value Get-DbaRegisteredServer }
if (-not (Test-Path Alias:Get-DbaRegisteredServerName)) { Set-Alias -Scope Global -Name Get-DbaRegisteredServerName -Value Get-DbaRegisteredServer }
if (-not (Test-Path Alias:Get-SqlServerKey)) { Set-Alias -Scope Global -Name Get-SqlServerKey -Value Get-DbaSqlProductKey }
if (-not (Test-Path Alias:Import-SqlSpConfigure)) { Set-Alias -Scope Global -Name Import-SqlSpConfigure -Value Import-DbaSpConfigure }
if (-not (Test-Path Alias:Install-SqlWhoIsActive)) { Set-Alias -Scope Global -Name Install-SqlWhoIsActive -Value Install-DbaWhoIsActive }
if (-not (Test-Path Alias:Invoke-DbaSqlcmd)) { Set-Alias -Scope Global -Name Invoke-DbaSqlcmd -Value Invoke-Sqlcmd2 }
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
if (-not (Test-Path Alias:Set-DbaQueryStoreConfig)) { Set-Alias -Scope Global -Name Set-DbaQueryStoreConfig -Value Set-DbaDbQueryStoreOptions }
if (-not (Test-Path Alias:Get-DbaQueryStoreConfig)) { Set-Alias -Scope Global -Name Get-DbaQueryStoreConfig -Value Get-DbaDbQueryStoreOptions }
if (-not (Test-Path Alias:Connect-DbaSqlServer)) { Set-Alias -Scope Global -Name Connect-DbaSqlServer -Value Connect-DbaInstance }
if (-not (Test-Path Alias:Get-DbaInstance)) { Set-Alias -Scope Global -Name Get-DbaInstance -Value Connect-DbaInstance }
if (-not (Test-Path Alias:Get-DbaXEventSession)) { Set-Alias -Scope Global -Name Get-DbaXEventSession -Value Get-DbaXESession }
if (-not (Test-Path Alias:Get-DbaXEventSessionTarget)) { Set-Alias -Scope Global -Name Get-DbaXEventSessionTarget -Value Get-DbaXESessionTarget }
if (-not (Test-Path Alias:Read-DbaXEventFile)) { Set-Alias -Scope Global -Name Read-DbaXEventFile -Value Read-DbaXEFile }
if (-not (Test-Path Alias:Watch-DbaXEventSession)) { Set-Alias -Scope Global -Name Watch-DbaXEventSession -Value Watch-DbaXESession }


# Leave forever
Set-Alias -Scope Global -Name Attach-DbaDatabase -Value Mount-DbaDatabase
Set-Alias -Scope Global -Name Detach-DbaDatabase -Value Dismount-DbaDatabase

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

$timeout = 10000
$timeSpent = 0
while (($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') -or ($script:dbatoolsConfigRunspace.Runspace.RunspaceAvailability -eq 'Busy'))
{
	Start-Sleep -Milliseconds 50
	$timeSpent = $timeSpent + 50
	
	if ($timeSpent -ge $timeout) {
		Write-Warning @"
The module import has hit a timeout while waiting for some background tasks to finish.
This may result in some commands not working as intended.
This should not happen under reasonable circumstances, please file an issue at:
https://github.com/sqlcollaborative/dbatools/issues
Or contact us directly in the #dbatools channel of the SQL Server Community Slack Channel:
https://dbatools.io/slack/
Timeout waiting for temporary runspaces reached! The Module import will complete, but some things may not work as intended
"@
		$global:smoRunspace = $script:smoRunspace
		$global:dbatoolsConfigRunspace = $script:dbatoolsConfigRunspace
		break
	}
}

if ($script:smoRunspace)
{
	$script:smoRunspace.Runspace.Close()
	$script:smoRunspace.Runspace.Dispose()
	$script:smoRunspace.Dispose()
	Remove-Variable -Name smoRunspace -Scope script
}

if ($script:dbatoolsConfigRunspace)
{
	$script:dbatoolsConfigRunspace.Runspace.Close()
	$script:dbatoolsConfigRunspace.Runspace.Dispose()
	$script:dbatoolsConfigRunspace.Dispose()
	Remove-Variable -Name dbatoolsConfigRunspace -Scope script
}

[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true;
Write-ImportTime -Text "Waiting for runspaces to finish"
#endregion Post-Import Cleanup

# SIG # Begin signature block
# MIIcYgYJKoZIhvcNAQcCoIIcUzCCHE8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUyZg9qEp4cTQPDr/+mbpNXT2l
# ASWggheRMIIFGjCCBAKgAwIBAgIQAsF1KHTVwoQxhSrYoGRpyjANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTE3MDUwOTAwMDAwMFoXDTIwMDUx
# MzEyMDAwMFowVzELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMQ8wDQYD
# VQQHEwZWaWVubmExETAPBgNVBAoTCGRiYXRvb2xzMREwDwYDVQQDEwhkYmF0b29s
# czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAI8ng7JxnekL0AO4qQgt
# Kr6p3q3SNOPh+SUZH+SyY8EA2I3wR7BMoT7rnZNolTwGjUXn7bRC6vISWg16N202
# 1RBWdTGW2rVPBVLF4HA46jle4hcpEVquXdj3yGYa99ko1w2FOWzLjKvtLqj4tzOh
# K7wa/Gbmv0Si/FU6oOmctzYMI0QXtEG7lR1HsJT5kywwmgcjyuiN28iBIhT6man0
# Ib6xKDv40PblKq5c9AFVldXUGVeBJbLhcEAA1nSPSLGdc7j4J2SulGISYY7ocuX3
# tkv01te72Mv2KkqqpfkLEAQjXgtM0hlgwuc8/A4if+I0YtboCMkVQuwBpbR9/6ys
# Z+sCAwEAAaOCAcUwggHBMB8GA1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB0GA1UdDgQWBBRcxSkFqeA3vvHU0aq2mVpFRSOdmjAOBgNVHQ8BAf8EBAMCB4Aw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEwG
# A1UdIARFMEMwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3
# LmRpZ2ljZXJ0LmNvbS9DUFMwCAYGZ4EMAQQBMIGEBggrBgEFBQcBAQR4MHYwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBOBggrBgEFBQcwAoZC
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJ
# RENvZGVTaWduaW5nQ0EuY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQAD
# ggEBANuBGTbzCRhgG0Th09J0m/qDqohWMx6ZOFKhMoKl8f/l6IwyDrkG48JBkWOA
# QYXNAzvp3Ro7aGCNJKRAOcIjNKYef/PFRfFQvMe07nQIj78G8x0q44ZpOVCp9uVj
# sLmIvsmF1dcYhOWs9BOG/Zp9augJUtlYpo4JW+iuZHCqjhKzIc74rEEiZd0hSm8M
# asshvBUSB9e8do/7RhaKezvlciDaFBQvg5s0fICsEhULBRhoyVOiUKUcemprPiTD
# xh3buBLuN0bBayjWmOMlkG1Z6i8DUvWlPGz9jiBT3ONBqxXfghXLL6n8PhfppBhn
# daPQO8+SqF5rqrlyBPmRRaTz2GQwggUwMIIEGKADAgECAhAECRgbX9W7ZnVTQ7Vv
# lVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBaFw0yODEw
# MjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/lqJ3bMtdx
# 6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fTeyOU5JEj
# lpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqHCN8M9eJN
# YBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+bMt+dDk2
# DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLoLFH3c7y9
# hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIByTASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAKBghghkgB
# hv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0jBBgwFoAU
# Reuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7sDVoks/Mi
# 0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGSdQ9RtG6l
# jlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6r7VRwo0k
# riTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo+MUSaJ/P
# QMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qzsIzV6Q3d
# 9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHqaGxEMrJm
# oecYpJpkUe8wggZqMIIFUqADAgECAhADAZoCOv9YsWvW1ermF/BmMA0GCSqGSIb3
# DQEBBQUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3Vy
# ZWQgSUQgQ0EtMTAeFw0xNDEwMjIwMDAwMDBaFw0yNDEwMjIwMDAwMDBaMEcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQKEwhEaWdpQ2VydDElMCMGA1UEAxMcRGlnaUNlcnQg
# VGltZXN0YW1wIFJlc3BvbmRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAKNkXfx8s+CCNeDg9sYq5kl1O8xu4FOpnx9kWeZ8a39rjJ1V+JLjntVaY1sC
# SVDZg85vZu7dy4XpX6X51Id0iEQ7Gcnl9ZGfxhQ5rCTqqEsskYnMXij0ZLZQt/US
# s3OWCmejvmGfrvP9Enh1DqZbFP1FI46GRFV9GIYFjFWHeUhG98oOjafeTl/iqLYt
# WQJhiGFyGGi5uHzu5uc0LzF3gTAfuzYBje8n4/ea8EwxZI3j6/oZh6h+z+yMDDZb
# esF6uHjHyQYuRhDIjegEYNu8c3T6Ttj+qkDxss5wRoPp2kChWTrZFQlXmVYwk/PJ
# YczQCMxr7GJCkawCwO+k8IkRj3cCAwEAAaOCAzUwggMxMA4GA1UdDwEB/wQEAwIH
# gDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIIBvwYDVR0g
# BIIBtjCCAbIwggGhBglghkgBhv1sBwEwggGSMCgGCCsGAQUFBwIBFhxodHRwczov
# L3d3dy5kaWdpY2VydC5jb20vQ1BTMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4A
# eQAgAHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQA
# ZQAgAGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUA
# IABvAGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAA
# YQBuAGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcA
# cgBlAGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIA
# aQBsAGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQA
# ZQBkACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsG
# CWCGSAGG/WwDFTAfBgNVHSMEGDAWgBQVABIrE5iymQftHt+ivlcNK2cCzTAdBgNV
# HQ4EFgQUYVpNJLZJMp1KKnkag0v0HonByn0wfQYDVR0fBHYwdDA4oDagNIYyaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcmww
# OKA2oDSGMmh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RENBLTEuY3JsMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURDQS0xLmNydDANBgkqhkiG9w0BAQUF
# AAOCAQEAnSV+GzNNsiaBXJuGziMgD4CH5Yj//7HUaiwx7ToXGXEXzakbvFoWOQCd
# 42yE5FpA+94GAYw3+puxnSR+/iCkV61bt5qwYCbqaVchXTQvH3Gwg5QZBWs1kBCg
# e5fH9j/n4hFBpr1i2fAnPTgdKG86Ugnw7HBi02JLsOBzppLA044x2C/jbRcTBu7k
# A7YUq/OPQ6dxnSHdFMoVXZJB2vkPgdGZdA0mxA5/G7X1oPHGdwYoFenYk+VVFvC7
# Cqsc21xIJ2bIo4sKHOWV2q7ELlmgYd3a822iYemKC23sEhi991VUQAOSK2vCUcIK
# SK+w1G7g9BQKOhvjjz3Kr2qNe9zYRDCCBs0wggW1oAMCAQICEAb9+QOWA63qAArr
# Pye7uhswDQYJKoZIhvcNAQEFBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMb
# RGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTA2MTExMDAwMDAwMFoXDTIx
# MTExMDAwMDAwMFowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# QXNzdXJlZCBJRCBDQS0xMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# 6IItmfnKwkKVpYBzQHDSnlZUXKnE0kEGj8kz/E1FkVyBn+0snPgWWd+etSQVwpi5
# tHdJ3InECtqvy15r7a2wcTHrzzpADEZNk+yLejYIA6sMNP4YSYL+x8cxSIB8HqIP
# kg5QycaH6zY/2DDD/6b3+6LNb3Mj/qxWBZDwMiEWicZwiPkFl32jx0PdAug7Pe2x
# QaPtP77blUjE7h6z8rwMK5nQxl0SQoHhg26Ccz8mSxSQrllmCsSNvtLOBq6thG9I
# hJtPQLnxTPKvmPv2zkBdXPao8S+v7Iki8msYZbHBc63X8djPHgp0XEK4aH631XcK
# J1Z8D2KkPzIUYJX9BwSiCQIDAQABo4IDejCCA3YwDgYDVR0PAQH/BAQDAgGGMDsG
# A1UdJQQ0MDIGCCsGAQUFBwMBBggrBgEFBQcDAgYIKwYBBQUHAwMGCCsGAQUFBwME
# BggrBgEFBQcDCDCCAdIGA1UdIASCAckwggHFMIIBtAYKYIZIAYb9bAABBDCCAaQw
# OgYIKwYBBQUHAgEWLmh0dHA6Ly93d3cuZGlnaWNlcnQuY29tL3NzbC1jcHMtcmVw
# b3NpdG9yeS5odG0wggFkBggrBgEFBQcCAjCCAVYeggFSAEEAbgB5ACAAdQBzAGUA
# IABvAGYAIAB0AGgAaQBzACAAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBvAG4A
# cwB0AGkAdAB1AHQAZQBzACAAYQBjAGMAZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQA
# aABlACAARABpAGcAaQBDAGUAcgB0ACAAQwBQAC8AQwBQAFMAIABhAG4AZAAgAHQA
# aABlACAAUgBlAGwAeQBpAG4AZwAgAFAAYQByAHQAeQAgAEEAZwByAGUAZQBtAGUA
# bgB0ACAAdwBoAGkAYwBoACAAbABpAG0AaQB0ACAAbABpAGEAYgBpAGwAaQB0AHkA
# IABhAG4AZAAgAGEAcgBlACAAaQBuAGMAbwByAHAAbwByAGEAdABlAGQAIABoAGUA
# cgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUAcgBlAG4AYwBlAC4wCwYJYIZIAYb9bAMV
# MBIGA1UdEwEB/wQIMAYBAf8CAQAweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQw
# gYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwHQYDVR0OBBYEFBUA
# EisTmLKZB+0e36K+Vw0rZwLNMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3z
# bcgPMA0GCSqGSIb3DQEBBQUAA4IBAQBGUD7Jtygkpzgdtlspr1LPUukxR6tWXHvV
# DQtBs+/sdR90OPKyXGGinJXDUOSCuSPRujqGcq04eKx1XRcXNHJHhZRW0eu7NoR3
# zCSl8wQZVann4+erYs37iy2QwsDStZS9Xk+xBdIOPRqpFFumhjFiqKgz5Js5p8T1
# zh14dpQlc+Qqq8+cdkvtX8JLFuRLcEwAiR78xXm8TBJX/l/hHrwCXaj++wc4Tw3G
# XZG5D2dFzdaD7eeSDY2xaYxP+1ngIw/Sqq4AfO6cQg7PkdcntxbuD8O9fAqg7iwI
# VYUiuOsYGk38KiGtSTGDR5V3cdyxG0tLHBCcdxTBnU8vWpUIKRAmMYIEOzCCBDcC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQAsF1KHTVwoQxhSrYoGRpyjAJBgUr
# DgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMx
# DAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkq
# hkiG9w0BCQQxFgQUarmgu5RSv0EmIvb21sIpxHtDwXQwDQYJKoZIhvcNAQEBBQAE
# ggEAM3MR4843G7O7OLZAUKzTpL2GBvkX6yNe5BLbLZsoivxBk4LxegQejmsxHenW
# QQnzJUTohp4RVKEE+WlVf1MbqvtQx+PEJSMq2qvC38duboC9OTdUg+1MlxXNtQ7M
# SPJ/l2MEtyCfPMnvrtSnWSqxCaKnCVx2rFS9TSkUA0+hQ1xNQeh4jk9vHKyBqY34
# XDJwKy4VFxK7EisOpaJN++ps63isErmmA3NXObVraYnuFetIfmT4GMYaBjpapKOb
# Lry8SeBHYPBAL/q9HD3RVSuNgsBnnkMZtj9p8ArfLr0Y9eNvuF4bdsJGdARxOdcn
# H8+c0jqUv7WTBjYkF9oVngeDYaGCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIB
# ATB2MGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQg
# SUQgQ0EtMQIQAwGaAjr/WLFr1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcN
# AQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTcxMTA5MjI1OTI4WjAj
# BgkqhkiG9w0BCQQxFgQUW+g4dRVO2UPu8dB4XSduC428JXwwDQYJKoZIhvcNAQEB
# BQAEggEANpg7HHpjwnJqUEHzZQXevBogvhjWQokKPDCNZ2YqIQxYAcFV308SFDNQ
# H8IfAkbzYDWVW7mlSaOKlI+VJGzHGIBDO/yme6sPF+StNLg4l+MagTJ1cUfrBI3K
# Tw8ipX20+ojxJdW5j3wD73RQyIe1iUilQM7tjObF+QPwrpHAi1+B4VoE9m7rVZO/
# NjFCcQouNzKF/3lV+oHAD+Bcwi5EtYCrC0unovTvvX8G/6L+YFmlSUSOqyFFuEVd
# P8sv+qBH/fausl4YYolU/0k3oMI8Pz6s3zKiwV3gUREd/lCnmrWlMGvV1l77afxF
# 8Yy2/KwDQzOC7qxPvHwcH0ye4N95Tw==
# SIG # End signature block
