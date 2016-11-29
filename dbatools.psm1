# All internal functions privately avaialble within the toolset
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\*.ps1")) { . $function }

# All exported functions
foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1")) { . $function }

# Not supporting the provider path at this time
# if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\")) { throw "Please change to another drive and reload the module." }

# I renamed this function to be more accurate
Set-Alias -Name Reset-SqlSaPassword -Value Reset-SqlAdmin
Set-Alias -Name Copy-SqlUserDefinedMessage -Value Copy-SqlCustomError
Set-Alias -Name Copy-SqlJobServer -Value Copy-SqlServerAgent
Set-Alias -Name Restore-HallengrenBackup -Value Restore-SqlBackupFromDirectory
Set-Alias -Name Show-SqlMigrationConstraint -Value Test-SqlMigrationConstraint
Set-Alias -Name Test-SqlDiskAllocation -Value Test-DbaDiskAllocation
Set-Alias -Name Get-DiskSpace -Value Get-DbaDiskSpace
Set-Alias -Name Get-SqlMaxMemory -Value Get-DbaMaxMemory
Set-Alias -Name Set-SqlMaxMemory -Value Set-DbaMaxMemory

# Strictmode coming when I've got time.
# Set-StrictMode -Version Latest

# In order to keep backwards compatability, these are loaded here instead of in the manifest.
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Dmf")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers")
$null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices")