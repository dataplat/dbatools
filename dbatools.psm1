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
    else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($Path))), $null, $null) }
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

# Not supporting the provider path at this time 2/28/2017
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\")) {
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

#region Copy DLL Mode
$script:copyDllMode = $false
if ($dbatools_copydllmode) { $script:copyDllMode = $true }
if ($dbatoolsSystemSystemNode.CopyDllMode) { $script:copyDllMode = $true }
if ($dbatoolsSystemUserNode.CopyDllMode) { $script:copyDllMode = $true }
#endregion Copy DLL Mode

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
Write-ImportTime -Text "Validated defines"
#endregion Import Defines

Get-ChildItem -Path "$script:PSModuleRoot\bin\*.dll" -Recurse | Unblock-File -ErrorAction SilentlyContinue
Write-ImportTime -Text "Unblocking Files"

# Define folder in which to copy dll files before importing
if (-not $script:copyDllMode) { $script:DllRoot = "$script:PSModuleRoot\bin" }
else {
    $libraryTempPath = "$($env:TEMP)\dbatools-$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    while (Test-Path -Path $libraryTempPath) {
        $libraryTempPath = "$($env:TEMP)\dbatools-$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    }
    $script:DllRoot = $libraryTempPath
    $null = New-Item -Path $libraryTempPath -ItemType Directory
}

if (-not ([System.Management.Automation.PSTypeName]'Microsoft.SqlServer.Management.Smo.Server').Type) {
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
if (-not ([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported)) {
    . Import-ModuleFile "$script:PSModuleRoot\internal\configurations\configuration.ps1"
    Write-ImportTime -Text "Configuration System"
}
if (-not ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::LoggingPath = "$($env:AppData)\PowerShell\dbatools"
}

if ((Test-Path -Path "$script:PSModuleRoot\.git")) {
    # All internal functions privately available within the toolset
    foreach ($function in (Get-ChildItem "$script:PSModuleRoot\internal\functions\*.ps1")) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"
    
    # All exported functions
    foreach ($function in (Get-ChildItem "$script:PSModuleRoot\functions\*.ps1")) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"
    
}
else {
    . "$script:PSModuleRoot\allcommands.ps1"
    Write-ImportTime -Text "Loading Public and Private Commands"
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem "$script:PSModuleRoot\optional\*.ps1")) {
    . Import-ModuleFile $function.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\insertTepp.ps1"
Write-ImportTime -Text "Loading TEPP"


# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\logfilescript.ps1"
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\updateTeppAsync.ps1"
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\dbatools-maintenance.ps1"
Write-ImportTime -Text "Script: Maintenance"

#region Aliases
# I renamed this function to be more accurate - 1ms
@(
    @{
        "AliasName"   = "Copy-SqlAgentCategory"
        "Definition"  = "Copy-DbaAgentCategory"
    },
    @{
        "AliasName"   = "Copy-SqlAlert"
        "Definition"  = "Copy-DbaAgentAlert"
    },
    @{
        "AliasName"   = "Copy-SqlAudit"
        "Definition"  = "Copy-DbaServerAudit"
    },
    @{
        "AliasName"   = "Copy-SqlAuditSpecification"
        "Definition"  = "Copy-DbaServerAuditSpecification"
    },
    @{
        "AliasName"   = "Copy-SqlBackupDevice"
        "Definition"  = "Copy-DbaBackupDevice"
    },
    @{
        "AliasName"   = "Copy-SqlCentralManagementServer"
        "Definition"  = "Copy-DbaCentralManagementServer"
    },
    @{
        "AliasName"   = "Copy-SqlCredential"
        "Definition"  = "Copy-DbaCredential"
    },
    @{
        "AliasName"   = "Copy-SqlCustomError"
        "Definition"  = "Copy-DbaCustomError"
    },
    @{
        "AliasName"   = "Copy-SqlDatabase"
        "Definition"  = "Copy-DbaDatabase"
    },
    @{
        "AliasName"   = "Copy-SqlDatabaseAssembly"
        "Definition"  = "Copy-DbaDatabaseAssembly"
    },
    @{
        "AliasName"   = "Copy-SqlDatabaseMail"
        "Definition"  = "Copy-DbaDatabaseMail"
    },
    @{
        "AliasName"   = "Copy-SqlDataCollector"
        "Definition"  = "Copy-DbaSqlDataCollector"
    },
    @{
        "AliasName"   = "Copy-SqlEndpoint"
        "Definition"  = "Copy-DbaEndpoint"
    },
    @{
        "AliasName"   = "Copy-SqlExtendedEvent"
        "Definition"  = "Copy-DbaExtendedEvent"
    },
    @{
        "AliasName"   = "Copy-SqlJob"
        "Definition"  = "Copy-DbaAgentJob"
    },
    @{
        "AliasName"   = "Copy-SqlJobServer"
        "Definition"  = "Copy-SqlServerAgent"
    },
    @{
        "AliasName"   = "Copy-SqlLinkedServer"
        "Definition"  = "Copy-DbaLinkedServer"
    },
    @{
        "AliasName"   = "Copy-SqlLogin"
        "Definition"  = "Copy-DbaLogin"
    },
    @{
        "AliasName"   = "Copy-SqlOperator"
        "Definition"  = "Copy-DbaAgentOperator"
    },
    @{
        "AliasName"   = "Copy-SqlPolicyManagement"
        "Definition"  = "Copy-DbaSqlPolicyManagement"
    },
    @{
        "AliasName"   = "Copy-SqlProxyAccount"
        "Definition"  = "Copy-DbaAgentProxyAccount"
    },
    @{
        "AliasName"   = "Copy-SqlResourceGovernor"
        "Definition"  = "Copy-DbaResourceGovernor"
    },
    @{
        "AliasName"   = "Copy-SqlServerAgent"
        "Definition"  = "Copy-DbaSqlServerAgent"
    },
    @{
        "AliasName"   = "Copy-SqlServerTrigger"
        "Definition"  = "Copy-DbaServerTrigger"
    },
    @{
        "AliasName"   = "Copy-SqlSharedSchedule"
        "Definition"  = "Copy-DbaAgentSharedSchedule"
    },
    @{
        "AliasName"   = "Copy-SqlSpConfigure"
        "Definition"  = "Copy-DbaSpConfigure"
    },
    @{
        "AliasName"   = "Copy-SqlSsisCatalog"
        "Definition"  = "Copy-DbaSsisCatalog"
    },
    @{
        "AliasName"   = "Copy-SqlSysDbUserObjects"
        "Definition"  = "Copy-DbaSysDbUserObject"
    },
    @{
        "AliasName"   = "Copy-SqlUserDefinedMessage"
        "Definition"  = "Copy-SqlCustomError"
    },
    @{
        "AliasName"   = "Expand-SqlTLogResponsibly"
        "Definition"  = "Expand-DbaTLogResponsibly"
    },
    @{
        "AliasName"   = "Export-SqlLogin"
        "Definition"  = "Export-DbaLogin"
    },
    @{
        "AliasName"   = "Export-SqlSpConfigure"
        "Definition"  = "Export-DbaSpConfigure"
    },
    @{
        "AliasName"   = "Export-SqlUser"
        "Definition"  = "Export-DbaUser"
    },
    @{
        "AliasName"   = "Find-SqlDuplicateIndex"
        "Definition"  = "Find-DbaDuplicateIndex"
    },
    @{
        "AliasName"   = "Find-SqlUnusedIndex"
        "Definition"  = "Find-DbaUnusedIndex"
    },
    @{
        "AliasName"   = "Get-SqlMaxMemory"
        "Definition"  = "Get-DbaMaxMemory"
    },
    @{
        "AliasName"   = "Get-SqlRegisteredServerName"
        "Definition"  = "Get-DbaRegisteredServer"
    },
    @{
        "AliasName"   = "Get-DbaRegisteredServerName"
        "Definition"  = "Get-DbaRegisteredServer"
    },
    @{
        "AliasName"   = "Get-SqlServerKey"
        "Definition"  = "Get-DbaSqlProductKey"
    },
    @{
        "AliasName"   = "Import-SqlSpConfigure"
        "Definition"  = "Import-DbaSpConfigure"
    },
    @{
        "AliasName"   = "Install-SqlWhoIsActive"
        "Definition"  = "Install-DbaWhoIsActive"
    },
    @{
        "AliasName"   = "Remove-SqlDatabaseSafely"
        "Definition"  = "Remove-DbaDatabaseSafely"
    },
    @{
        "AliasName"   = "Remove-SqlOrphanUser"
        "Definition"  = "Remove-DbaOrphanUser"
    },
    @{
        "AliasName"   = "Repair-SqlOrphanUser"
        "Definition"  = "Repair-DbaOrphanUser"
    },
    @{
        "AliasName"   = "Reset-SqlAdmin"
        "Definition"  = "Reset-DbaAdmin"
    },
    @{
        "AliasName"   = "Reset-SqlSaPassword"
        "Definition"  = "Reset-SqlAdmin"
    },
    @{
        "AliasName"   = "Restore-SqlBackupFromDirectory"
        "Definition"  = "Restore-DbaBackupFromDirectory"
    },
    @{
        "AliasName"   = "Set-SqlMaxMemory"
        "Definition"  = "Set-DbaMaxMemory"
    },
    @{
        "AliasName"   = "Set-SqlTempDbConfiguration"
        "Definition"  = "Set-DbaTempDbConfiguration"
    },
    @{
        "AliasName"   = "Show-SqlDatabaseList"
        "Definition"  = "Show-DbaDatabaseList"
    },
    @{
        "AliasName"   = "Show-SqlMigrationConstraint"
        "Definition"  = "Test-SqlMigrationConstraint"
    },
    @{
        "AliasName"   = "Show-SqlServerFileSystem"
        "Definition"  = "Show-DbaServerFileSystem"
    },
    @{
        "AliasName"   = "Show-SqlWhoIsActive"
        "Definition"  = "Invoke-DbaWhoIsActive"
    },
    @{
        "AliasName"   = "Start-SqlMigration"
        "Definition"  = "Start-DbaMigration"
    },
    @{
        "AliasName"   = "Sync-SqlLoginPermissions"
        "Definition"  = "Sync-DbaSqlLoginPermission"
    },
    @{
        "AliasName"   = "Test-SqlConnection"
        "Definition"  = "Test-DbaConnection"
    },
    @{
        "AliasName"   = "Test-SqlDiskAllocation"
        "Definition"  = "Test-DbaDiskAllocation"
    },
    @{
        "AliasName"   = "Test-SqlMigrationConstraint"
        "Definition"  = "Test-DbaMigrationConstraint"
    },
    @{
        "AliasName"   = "Test-SqlNetworkLatency"
        "Definition"  = "Test-DbaNetworkLatency"
    },
    @{
        "AliasName"   = "Test-SqlPath"
        "Definition"  = "Test-DbaSqlPath"
    },
    @{
        "AliasName"   = "Test-SqlTempDbConfiguration"
        "Definition"  = "Test-DbaTempDbConfiguration"
    },
    @{
        "AliasName"   = "Watch-SqlDbLogin"
        "Definition"  = "Watch-DbaDbLogin"
    },
    @{
        "AliasName"   = "Get-DiskSpace"
        "Definition"  = "Get-DbaDiskSpace"
    },
    @{
        "AliasName"   = "Restore-HallengrenBackup"
        "Definition"  = "Restore-SqlBackupFromDirectory"
    },
    @{
        "AliasName"   = "Get-DbaDatabaseFreeSpace"
        "Definition"  = "Get-DbaDatabaseSpace"
    },
    @{
        "AliasName"   = "Set-DbaQueryStoreConfig"
        "Definition"  = "Set-DbaDbQueryStoreOptions"
    },
    @{
        "AliasName"   = "Get-DbaQueryStoreConfig"
        "Definition"  = "Get-DbaDbQueryStoreOptions"
    },
    @{
        "AliasName"   = "Connect-DbaSqlServer"
        "Definition"  = "Connect-DbaInstance"
    },
    @{
        "AliasName"   = "Get-DbaInstance"
        "Definition"  = "Connect-DbaInstance"
    },
    @{
        "AliasName"   = "Get-DbaXEventSession"
        "Definition"  = "Get-DbaXESession"
    },
    @{
        "AliasName"   = "Get-DbaXEventSessionTarget"
        "Definition"  = "Get-DbaXESessionTarget"
    },
    @{
        "AliasName"   = "Read-DbaXEventFile"
        "Definition"  = "Read-DbaXEFile"
    },
    @{
        "AliasName"   = "Watch-DbaXEventSession"
        "Definition"  = "Watch-DbaXESession"
    },
    @{
        "AliasName"   = "Get-DbaDatabaseCertificate"
        "Definition"  = "Get-DbaDbCertificate"
    },
    @{
        "AliasName"   = "New-DbaDatabaseCertificate"
        "Definition"  = "New-DbaDbCertificate"
    },
    @{
        "AliasName"   = "Remove-DbaDatabaseCertificate"
        "Definition"  = "Remove-DbaDbCertificate"
    },
    @{
        "AliasName"   = "Restore-DbaDatabaseCertificate"
        "Definition"  = "Restore-DbaDbCertificate"
    },
    @{
        "AliasName"   = "Backup-DbaDatabaseCertificate"
        "Definition"  = "Backup-DbaDbCertificate"
    },
    @{
        "AliasName"   = "Find-DbaDatabaseGrowthEvent"
        "Definition"  = "Find-DbaDbGrowthEvent"
    },
    @{
        "AliasName"    = "Get-DbaTraceFile"
        "Definition"   = "Get-DbaTrace"
    },
    @{
        "AliasName"   = "Out-DbaDataTable"
        "Definition"  = "ConvertTo-DbaDataTable"
    },
    @{
        "AliasName"    = "Invoke-DbaSqlCmd"
        "Definition"   = "Invoke-DbaSqlQuery"
    },
    @{
        "AliasName"     = "Test-DbaVirtualLogFile"
        "Definition"    = "Test-DbaDbVirtualLogFile"
    },
    @{
        "AliasName"      = "Test-DbaFullRecoveryModel"
        "Definition"     = "Test-DbaRecoveryModel"
    }
) | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}


# Leave forever
@(
    @{
        "AliasName"   = "Attach-DbaDatabase"
        "Definition"  = "Mount-DbaDatabase"
    },
    @{
        "AliasName"   = "Detach-DbaDatabase"
        "Definition"  = "Dismount-DbaDatabase"
    }
) | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}
#endregion Aliases

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

$timeout = 20000
$timeSpent = 0
while (($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') -or ($script:dbatoolsConfigRunspace.Runspace.RunspaceAvailability -eq 'Busy')) {
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

if ($script:smoRunspace) {
    $script:smoRunspace.Runspace.Close()
    $script:smoRunspace.Runspace.Dispose()
    $script:smoRunspace.Dispose()
    Remove-Variable -Name smoRunspace -Scope script
}

if ($script:dbatoolsConfigRunspace) {
    $script:dbatoolsConfigRunspace.Runspace.Close()
    $script:dbatoolsConfigRunspace.Runspace.Dispose()
    $script:dbatoolsConfigRunspace.Dispose()
    Remove-Variable -Name dbatoolsConfigRunspace -Scope script
}
Write-ImportTime -Text "Waiting for runspaces to finish"

if ($PSCommandPath -like "*.psm1") {
    Update-TypeData -AppendPath "$script:PSModuleRoot\xml\dbatools.Types.ps1xml"
    Write-ImportTime -Text "Loaded type extensions"
}
#. Import-ModuleFile "$script:PSModuleRoot\bin\type-extensions.ps1"
#Write-ImportTime -Text "Loaded type extensions"

[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true;

#endregion Post-Import Cleanup


# SIG # Begin signature block
# MIIcYgYJKoZIhvcNAQcCoIIcUzCCHE8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUcWbhzLgWmZGHIQQ5YiQIk8eF
# utiggheRMIIFGjCCBAKgAwIBAgIQAsF1KHTVwoQxhSrYoGRpyjANBgkqhkiG9w0B
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
# hkiG9w0BCQQxFgQUXQgZw8CgL73ZK5PXiOaX7v/4idYwDQYJKoZIhvcNAQEBBQAE
# ggEAY7tur8WDSUwFQZJt1M+bPuPFEIBLsR+Vb94hm05ti6fvW0v740RjMjzVApOf
# suOWilkI80B6NrkiGTOBMaqGrD69LuqJ45sR4+phyExmt8/3Cydc/61Vco8TQfu3
# c4xlU9d3m9EjGzacnbEkWYOrYQiekKBt7TFTuOfeGFhEMsLuR0YyoUQVyikAeBOA
# iRBGsgfq4A0Hg+2TVi0X9Y9HhodzwfQI1jwzKq2VO+y0VdLOo894p5WQQS0nErY5
# bwxkjJb6/MDHtfKj/BHVcYQMZv7W4Q6kBVwl2k6sKWeFC/qpyyLpiujVkmwT4+gH
# qoP2WaEdvt5EPz4rk9+89yalO6GCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIB
# ATB2MGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQg
# SUQgQ0EtMQIQAwGaAjr/WLFr1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcN
# AQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTgwNTA5MjEwMDExWjAj
# BgkqhkiG9w0BCQQxFgQU6iR1AiwGKv0YUo1M8cSvFtOcC5MwDQYJKoZIhvcNAQEB
# BQAEggEAfp9rwJEkb1iBhGWygv0PQPsd6mG1AcBCtugXWWxkQulgtQOaQxl6zfKY
# WcIMiBuKcCnOIP3+laREwdHGYZ2vATsz68yYiumIzK5sJKjn/61e8Uq4hL+ebE7B
# PFXjJYPv0DJbaIcewpCClBfPC+6eUISfnCcNudIJvDN1aRKoKAXWoubln9xdWZHY
# 37Jl1/xx9plqzvWK5s2OcnvG7XAgaS1vy5lpbvsMdPKS7I+zwxtRUUgs76RERvTc
# Kixevo/7LMxOMU+Ou58+KP53ebD3Tl3Vb9VueFhh2Q7ywmHyfs3DhsxesTcFUqjM
# oPsYdDshPEvgSGDYcHXrItyKyTNDNA==
# SIG # End signature block
