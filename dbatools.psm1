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
    param (
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
    param (
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

#region Multi File Import
$script:multiFileImport = $false
if ($dbatools_multiFileImport) { $script:multiFileImport = $true }
if ($dbatoolsSystemSystemNode.MultiFileImport) { $script:multiFileImport = $true }
if ($dbatoolsSystemUserNode.MultiFileImport) { $script:multiFileImport = $true }
if (Test-Path -Path "$script:PSModuleRoot\.git") { $script:multiFileImport = $true }
#endregion Multi File Import

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
if (-not ([Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = "$($env:AppData)\PowerShell\dbatools"
}

if ($script:multiFileImport) {
    # All internal functions privately available within the toolset
    foreach ($function in (Get-ChildItem "$script:PSModuleRoot\internal\functions\*.ps1")) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"

    . Import-ModuleFile "$script:PSModuleRoot\internal\scripts\cmdlets.ps1"
    Write-ImportTime -Text "Registering cmdlets"

    # All exported functions
    foreach ($function in (Get-ChildItem "$script:PSModuleRoot\functions\*.ps1")) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"

}
else {
    . "$script:PSModuleRoot\allcommands.ps1"
    Write-ImportTime -Text "Loading Public and Private Commands"

    . Import-ModuleFile "$script:PSModuleRoot\internal\scripts\cmdlets.ps1"
    Write-ImportTime -Text "Registering cmdlets"
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

# Process transforms
. Import-ModuleFile "$script:PSModuleRoot\internal\scripts\message-transforms.ps1"
Write-ImportTime -Text "Loading Message Transforms"

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
# changed to a script var so it can be used in the Rename-DbatoolsCommand
$script:renames = @(
    @{
        "AliasName"  = "Copy-SqlAgentCategory"
        "Definition" = "Copy-DbaAgentCategory"
    },
    @{
        "AliasName"  = "Copy-SqlAlert"
        "Definition" = "Copy-DbaAgentAlert"
    },
    @{
        "AliasName"  = "Copy-SqlAudit"
        "Definition" = "Copy-DbaServerAudit"
    },
    @{
        "AliasName"  = "Copy-SqlAuditSpecification"
        "Definition" = "Copy-DbaServerAuditSpecification"
    },
    @{
        "AliasName"  = "Copy-SqlBackupDevice"
        "Definition" = "Copy-DbaBackupDevice"
    },
    @{
        "AliasName"  = "Copy-SqlCentralManagementServer"
        "Definition" = "Copy-DbaCentralManagementServer"
    },
    @{
        "AliasName"  = "Copy-SqlCredential"
        "Definition" = "Copy-DbaCredential"
    },
    @{
        "AliasName"  = "Copy-SqlCustomError"
        "Definition" = "Copy-DbaCustomError"
    },
    @{
        "AliasName"  = "Copy-SqlDatabase"
        "Definition" = "Copy-DbaDatabase"
    },
    @{
        "AliasName"  = "Copy-SqlDatabaseAssembly"
        "Definition" = "Copy-DbaDbAssembly"
    },
    @{
        "AliasName"  = "Copy-SqlDatabaseMail"
        "Definition" = "Copy-DbaDbMail"
    },
    @{
        "AliasName"  = "Copy-SqlDataCollector"
        "Definition" = "Copy-DbaDataCollector"
    },
    @{
        "AliasName"  = "Copy-SqlEndpoint"
        "Definition" = "Copy-DbaEndpoint"
    },
    @{
        "AliasName"  = "Copy-SqlExtendedEvent"
        "Definition" = "Copy-DbaExtendedEvent"
    },
    @{
        "AliasName"  = "Copy-SqlJob"
        "Definition" = "Copy-DbaAgentJob"
    },
    @{
        "AliasName"  = "Copy-SqlJobServer"
        "Definition" = "Copy-SqlServerAgent"
    },
    @{
        "AliasName"  = "Copy-SqlLinkedServer"
        "Definition" = "Copy-DbaLinkedServer"
    },
    @{
        "AliasName"  = "Copy-SqlLogin"
        "Definition" = "Copy-DbaLogin"
    },
    @{
        "AliasName"  = "Copy-SqlOperator"
        "Definition" = "Copy-DbaAgentOperator"
    },
    @{
        "AliasName"  = "Copy-SqlPolicyManagement"
        "Definition" = "Copy-DbaPolicyManagement"
    },
    @{
        "AliasName"  = "Copy-SqlProxyAccount"
        "Definition" = "Copy-DbaAgentProxyAccount"
    },
    @{
        "AliasName"  = "Copy-SqlResourceGovernor"
        "Definition" = "Copy-DbaResourceGovernor"
    },
    @{
        "AliasName"  = "Copy-SqlServerAgent"
        "Definition" = "Copy-DbaAgentServer"
    },
    @{
        "AliasName"  = "Copy-SqlServerTrigger"
        "Definition" = "Copy-DbaServerTrigger"
    },
    @{
        "AliasName"  = "Copy-SqlSharedSchedule"
        "Definition" = "Copy-DbaAgentSharedSchedule"
    },
    @{
        "AliasName"  = "Copy-SqlSpConfigure"
        "Definition" = "Copy-DbaSpConfigure"
    },
    @{
        "AliasName"  = "Copy-SqlSsisCatalog"
        "Definition" = "Copy-DbaSsisCatalog"
    },
    @{
        "AliasName"  = "Copy-SqlSysDbUserObjects"
        "Definition" = "Copy-DbaSysDbUserObject"
    },
    @{
        "AliasName"  = "Copy-SqlUserDefinedMessage"
        "Definition" = "Copy-SqlCustomError"
    },
    @{
        "AliasName"  = "Expand-SqlTLogResponsibly"
        "Definition" = "Expand-DbaDbLogFile"
    },
    @{
        "AliasName"  = "Export-SqlLogin"
        "Definition" = "Export-DbaLogin"
    },
    @{
        "AliasName"  = "Export-SqlSpConfigure"
        "Definition" = "Export-DbaSpConfigure"
    },
    @{
        "AliasName"  = "Export-SqlUser"
        "Definition" = "Export-DbaUser"
    },
    @{
        "AliasName"  = "Find-SqlDuplicateIndex"
        "Definition" = "Find-DbaDuplicateIndex"
    },
    @{
        "AliasName"  = "Find-SqlUnusedIndex"
        "Definition" = "Find-DbaDbUnusedIndex"
    },
    @{
        "AliasName"  = "Get-SqlMaxMemory"
        "Definition" = "Get-DbaMaxMemory"
    },
    @{
        "AliasName"  = "Get-SqlRegisteredServerName"
        "Definition" = "Get-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Get-DbaCmsRegServerName"
        "Definition" = "Get-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Get-SqlServerKey"
        "Definition" = "Get-DbaProductKey"
    },
    @{
        "AliasName"  = "Import-SqlSpConfigure"
        "Definition" = "Import-DbaSpConfigure"
    },
    @{
        "AliasName"  = "Install-SqlWhoIsActive"
        "Definition" = "Install-DbaWhoIsActive"
    },
    @{
        "AliasName"  = "Remove-SqlDatabaseSafely"
        "Definition" = "Remove-DbaDatabaseSafely"
    },
    @{
        "AliasName"  = "Remove-SqlOrphanUser"
        "Definition" = "Remove-DbaOrphanUser"
    },
    @{
        "AliasName"  = "Repair-SqlOrphanUser"
        "Definition" = "Repair-DbaOrphanUser"
    },
    @{
        "AliasName"  = "Reset-SqlAdmin"
        "Definition" = "Reset-DbaAdmin"
    },
    @{
        "AliasName"  = "Reset-SqlSaPassword"
        "Definition" = "Reset-SqlAdmin"
    },
    @{
        "AliasName"  = "Restore-SqlBackupFromDirectory"
        "Definition" = "Restore-DbaBackupFromDirectory"
    },
    @{
        "AliasName"  = "Set-SqlMaxMemory"
        "Definition" = "Set-DbaMaxMemory"
    },
    @{
        "AliasName"  = "Set-SqlTempDbConfiguration"
        "Definition" = "Set-DbaTempdbConfig"
    },
    @{
        "AliasName"  = "Show-SqlDatabaseList"
        "Definition" = "Show-DbaDbList"
    },
    @{
        "AliasName"  = "Show-SqlMigrationConstraint"
        "Definition" = "Test-SqlMigrationConstraint"
    },
    @{
        "AliasName"  = "Show-SqlServerFileSystem"
        "Definition" = "Show-DbaServerFileSystem"
    },
    @{
        "AliasName"  = "Show-SqlWhoIsActive"
        "Definition" = "Invoke-DbaWhoIsActive"
    },
    @{
        "AliasName"  = "Start-SqlMigration"
        "Definition" = "Start-DbaMigration"
    },
    @{
        "AliasName"  = "Sync-SqlLoginPermissions"
        "Definition" = "Sync-DbaLoginPermission"
    },
    @{
        "AliasName"  = "Sync-DbaSqlLoginPermission"
        "Definition" = "Sync-DbaLoginPermission"
    },
    @{
        "AliasName"  = "Test-SqlConnection"
        "Definition" = "Test-DbaConnection"
    },
    @{
        "AliasName"  = "Test-SqlDiskAllocation"
        "Definition" = "Test-DbaDiskAllocation"
    },
    @{
        "AliasName"  = "Test-SqlMigrationConstraint"
        "Definition" = "Test-DbaMigrationConstraint"
    },
    @{
        "AliasName"  = "Test-SqlNetworkLatency"
        "Definition" = "Test-DbaNetworkLatency"
    },
    @{
        "AliasName"  = "Test-SqlPath"
        "Definition" = "Test-DbaPath"
    },
    @{
        "AliasName"  = "Test-SqlTempDbConfiguration"
        "Definition" = "Test-DbaTempdbConfig"
    },
    @{
        "AliasName"  = "Watch-SqlDbLogin"
        "Definition" = "Watch-DbaDbLogin"
    },
    @{
        "AliasName"  = "Get-DiskSpace"
        "Definition" = "Get-DbaDiskSpace"
    },
    @{
        "AliasName"  = "Restore-HallengrenBackup"
        "Definition" = "Restore-SqlBackupFromDirectory"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseFreeSpace"
        "Definition" = "Get-DbaDbSpace"
    },
    @{
        "AliasName"  = "Set-DbaQueryStoreConfig"
        "Definition" = "Set-DbaDbQueryStoreOption"
    },
    @{
        "AliasName"  = "Get-DbaQueryStoreConfig"
        "Definition" = "Get-DbaDbQueryStoreOption"
    },
    @{
        "AliasName"  = "Connect-DbaServer"
        "Definition" = "Connect-DbaInstance"
    },
    @{
        "AliasName"  = "Get-DbaInstance"
        "Definition" = "Connect-DbaInstance"
    },
    @{
        "AliasName"  = "Get-DbaXEventSession"
        "Definition" = "Get-DbaXESession"
    },
    @{
        "AliasName"  = "Get-DbaXEventSessionTarget"
        "Definition" = "Get-DbaXESessionTarget"
    },
    @{
        "AliasName"  = "Read-DbaXEventFile"
        "Definition" = "Read-DbaXEFile"
    },
    @{
        "AliasName"  = "Watch-DbaXEventSession"
        "Definition" = "Watch-DbaXESession"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseCertificate"
        "Definition" = "Get-DbaDbCertificate"
    },
    @{
        "AliasName"  = "New-DbaDatabaseCertificate"
        "Definition" = "New-DbaDbCertificate"
    },
    @{
        "AliasName"  = "Remove-DbaDatabaseCertificate"
        "Definition" = "Remove-DbaDbCertificate"
    },
    @{
        "AliasName"  = "Restore-DbaDatabaseCertificate"
        "Definition" = "Restore-DbaDbCertificate"
    },
    @{
        "AliasName"  = "Backup-DbaDatabaseCertificate"
        "Definition" = "Backup-DbaDbCertificate"
    },
    @{
        "AliasName"  = "Find-DbaDatabaseGrowthEvent"
        "Definition" = "Find-DbaDbGrowthEvent"
    },
    @{
        "AliasName"  = "Get-DbaTraceFile"
        "Definition" = "Get-DbaTrace"
    },
    @{
        "AliasName"  = "Out-DbaDataTable"
        "Definition" = "ConvertTo-DbaDataTable"
    },
    @{
        "AliasName"  = "Invoke-DbaCmd"
        "Definition" = "Invoke-DbaQuery"
    },
    @{
        "AliasName"  = "Test-DbaVirtualLogFile"
        "Definition" = "Test-DbaDbVirtualLogFile"
    },
    @{
        "AliasName"  = "Test-DbaFullRecoveryModel"
        "Definition" = "Test-DbaDbRecoveryModel"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseSnapshot"
        "Definition" = "Get-DbaDbSnapshot"
    },
    @{
        "AliasName"  = "New-DbaDatabaseSnapshot"
        "Definition" = "New-DbaDbSnapshot"
    },
    @{
        "AliasName"  = "Remove-DbaDatabaseSnapshot"
        "Definition" = "Remove-DbaDbSnapshot"
    },
    @{
        "AliasName"  = "Restore-DbaDatabaseSnapshot"
        "Definition" = "Restore-DbaDbSnapshot"
    },
    @{
        "AliasName"  = "Get-DbaLog"
        "Definition" = "Get-DbaErrorLog"
    },
    @{
        "AliasName"  = "Test-DbaValidLogin"
        "Definition" = "Test-DbaWindowsLogin"
    },
    @{
        "AliasName"  = "Get-DbaJobCategory"
        "Definition" = "Get-DbaAgentJobCategory"
    },
    @{
        "AliasName"  = "Invoke-DbaDatabaseShrink"
        "Definition" = "Invoke-DbaDbShrink"
    },
    @{
        "AliasName"  = "Get-DbaPolicy"
        "Definition" = "Get-DbaPbmPolicy"
    },
    @{
        "AliasName"  = "Backup-DbaDatabaseMasterKey"
        "Definition" = "Backup-DbaDbMasterKey"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseMasterKey"
        "Definition" = "Get-DbaDbMasterKey"
    },
    @{
        "AliasName"  = "Remove-DbaDatabaseMasterKey"
        "Definition" = "Remove-DbaDbMasterKey"
    },
    @{
        "AliasName"  = "New-DbaDatabaseMasterKey"
        "Definition" = "New-DbaDbMasterKey"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseAssembly"
        "Definition" = "Get-DbaDbAssembly"
    },
    @{
        "AliasName"  = "Copy-DbaDatabaseAssembly"
        "Definition" = "Copy-DbaDbAssembly"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseEncryption"
        "Definition" = "Get-DbaDbEncryption"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseFile"
        "Definition" = "Get-DbaDbFile"
    },
    @{
        "AliasName"  = "Get-DbaDatabasePartitionFunction"
        "Definition" = "Get-DbaDbPartitionFunction"
    },
    @{
        "AliasName"  = "Get-DbaDatabasePartitionScheme"
        "Definition" = "Get-DbaDbPartitionScheme"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseSpace"
        "Definition" = "Get-DbaDbSpace"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseState"
        "Definition" = "Get-DbaDbState"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseUdf"
        "Definition" = "Get-DbaDbUdf"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseUser"
        "Definition" = "Get-DbaDbUser"
    },
    @{
        "AliasName"  = "Get-DbaDatabaseView"
        "Definition" = "Get-DbaDbView"
    },
    @{
        "AliasName"  = "Invoke-DbaDatabaseClone"
        "Definition" = "Invoke-DbaDbClone"
    },
    @{
        "AliasName"  = "Invoke-DbaDatabaseUpgrade"
        "Definition" = "Invoke-DbaDbUpgrade"
    },
    @{
        "AliasName"  = "Set-DbaDatabaseOwner"
        "Definition" = "Set-DbaDbOwner"
    },
    @{
        "AliasName"  = "Set-DbaDatabaseState"
        "Definition" = "Set-DbaDbState"
    },
    @{
        "AliasName"  = "Show-DbaDatabaseList"
        "Definition" = "Show-DbaDbList"
    },
    @{
        "AliasName"  = "Test-DbaDatabaseCollation"
        "Definition" = "Test-DbaDbCollation"
    },
    @{
        "AliasName"  = "Test-DbaDatabaseCompatibility"
        "Definition" = "Test-DbaDbCompatibility"
    },
    @{
        "AliasName"  = "Test-DbaDatabaseOwner"
        "Definition" = "Test-DbaDbOwner"
    },
    @{
        "AliasName"  = "Clear-DbaSqlConnectionPool"
        "Definition" = "Clear-DbaConnectionPool"
    },
    @{
        "AliasName"  = "Copy-DbaSqlDataCollector"
        "Definition" = "Copy-DbaDataCollector"
    },
    @{
        "AliasName"  = "Copy-DbaSqlPolicyManagement"
        "Definition" = "Copy-DbaPolicyManagement"
    },
    @{
        "AliasName"  = "Copy-DbaSqlServerAgent"
        "Definition" = "Copy-DbaAgentServer"
    },
    @{
        "AliasName"  = "Get-DbaSqlBuildReference"
        "Definition" = "Get-DbaBuildReference"
    },
    @{
        "AliasName"  = "Get-DbaSqlFeature"
        "Definition" = "Get-DbaFeature"
    },
    @{
        "AliasName"  = "Get-DbaSqlInstanceProperty"
        "Definition" = "Get-DbaInstanceProperty"
    },
    @{
        "AliasName"  = "Get-DbaSqlInstanceUserOption"
        "Definition" = "Get-DbaInstanceUserOption"
    },
    @{
        "AliasName"  = "Get-DbaSqlManagementObject"
        "Definition" = "Get-DbaManagementObject"
    },
    @{
        "AliasName"  = "Get-DbaSqlModule"
        "Definition" = "Get-DbaModule"
    },
    @{
        "AliasName"  = "Get-DbaSqlProductKey"
        "Definition" = "Get-DbaProductKey"
    },
    @{
        "AliasName"  = "Get-DbaSqlRegistryRoot"
        "Definition" = "Get-DbaRegistryRoot"
    },
    @{
        "AliasName"  = "Get-DbaSqlService"
        "Definition" = "Get-DbaService"
    },
    @{
        "AliasName"  = "Invoke-DbaSqlQuery"
        "Definition" = "Invoke-DbaQuery"
    },
    @{
        "AliasName"  = "New-DbaSqlConnectionString"
        "Definition" = "New-DbaConnectionString"
    },
    @{
        "AliasName"  = "New-DbaSqlConnectionStringBuilder"
        "Definition" = "New-DbaConnectionStringBuilder"
    },
    @{
        "AliasName"  = "New-DbaSqlDirectory"
        "Definition" = "New-DbaDirectory"
    },
    @{
        "AliasName"  = "Restart-DbaSqlService"
        "Definition" = "Restart-DbaService"
    },
    @{
        "AliasName"  = "Start-DbaSqlService"
        "Definition" = "Start-DbaService"
    },
    @{
        "AliasName"  = "Stop-DbaSqlService"
        "Definition" = "Stop-DbaService"
    },
    @{
        "AliasName"  = "Test-DbaSqlBuild"
        "Definition" = "Test-DbaBuild"
    },
    @{
        "AliasName"  = "Test-DbaSqlManagementObject"
        "Definition" = "Test-DbaManagementObject"
    },
    @{
        "AliasName"  = "Test-DbaSqlPath"
        "Definition" = "Test-DbaPath"
    },
    @{
        "AliasName"  = "Update-DbaSqlServiceAccount"
        "Definition" = "Update-DbaServiceAccount"
    },
    @{
        "AliasName"  = "Set-DbaTempDbConfiguration"
        "Definition" = "Set-DbaTempdbConfig"
    },
    @{
        "AliasName"  = "Test-DbaTempDbConfiguration"
        "Definition" = "Test-DbaTempdbConfig"
    },
    @{
        "AliasName"  = "Export-DbaDacpac"
        "Definition" = "Export-DbaDacPackage"
    },
    @{
        "AliasName"  = "Publish-DbaDacpac"
        "Definition" = "Publish-DbaDacPackage"
    },
    @{
        "AliasName"  = "Get-DbaConfig"
        "Definition" = "Get-DbatoolsConfig"
    },
    @{
        "AliasName"  = "Set-DbaConfig"
        "Definition" = "Set-DbatoolsConfig"
    },
    @{
        "AliasName"  = "Get-DbaConfigValue"
        "Definition" = "Get-DbatoolsConfigValue"
    },
    @{
        "AliasName"  = "Register-DbaConfig"
        "Definition" = "Register-DbatoolsConfig"
    },
    @{
        "AliasName"  = "New-DbaPublishProfile"
        "Definition" = "New-DbaDacProfile"
    },
    @{
        "AliasName"  = "Get-DbaDbQueryStoreOptions"
        "Definition" = "Get-DbaDbQueryStoreOption"
    },
    @{
        "AliasName"  = "Set-DbaDbQueryStoreOptions"
        "Definition" = "Set-DbaDbQueryStoreOption"
    },
    @{
        "AliasName"  = "Copy-DbaDatabaseMail"
        "Definition" = "Copy-DbaDbMail"
    },
    @{
        "AliasName"  = "Get-DbaUserLevelPermission"
        "Definition" = "Get-DbaUserPermission"
    },
    @{
        "AliasName"  = "Get-DbaDistributor"
        "Definition" = "Get-DbaRepDistributor"
    },
    @{
        "AliasName"  = "Get-DbaTable"
        "Definition" = "Get-DbaDbTable"
    },
    @{
        "AliasName"  = "Copy-DbaTableData"
        "Definition" = "Copy-DbaDbTableData"
    }, @{
        "AliasName"  = "Add-DbaRegisteredServer"
        "Definition" = "Add-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Add-DbaRegisteredServerGroup"
        "Definition" = "Add-DbaCmsRegServerGroup"
    },
    @{
        "AliasName"  = "Export-DbaRegisteredServer"
        "Definition" = "Export-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Get-DbaRegisteredServer"
        "Definition" = "Get-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Get-DbaRegisteredServerGroup"
        "Definition" = "Get-DbaCmsRegServerGroup"
    },
    @{
        "AliasName"  = "Get-DbaRegisteredServerStore"
        "Definition" = "Get-DbaCmsRegServerStore"
    },
    @{
        "AliasName"  = "Import-DbaRegisteredServer"
        "Definition" = "Import-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Move-DbaRegisteredServer"
        "Definition" = "Move-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Move-DbaRegisteredServerGroup"
        "Definition" = "Move-DbaCmsRegServerGroup"
    },
    @{
        "AliasName"  = "Remove-DbaRegisteredServer"
        "Definition" = "Remove-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Remove-DbaRegisteredServerGroup"
        "Definition" = "Remove-DbaCmsRegServerGroup"
    },
    @{
        "AliasName"  = "Get-DbaLogShippingError"
        "Definition" = "Get-DbaDbLogShipError"
    },
    @{
        "AliasName"  = "Invoke-DbaLogShipping"
        "Definition" = "Invoke-DbaDbLogShipping"
    },
    @{
        "AliasName"  = "Invoke-DbaLogShippingRecovery"
        "Definition" = "Invoke-DbaDbLogShipRecovery"
    },
    @{
        "AliasName"  = "Test-DbaLogShippingStatus"
        "Definition" = "Test-DbaDbLogShipStatus"
    },
    @{
        "AliasName"  = "Get-DbaRoleMember"
        "Definition" = "Get-DbaDbRoleMember"
    },
    @{
        "AliasName"  = "Get-DbaRestoreHistory"
        "Definition" = "Get-DbaDbRestoreHistory"
    },
    @{
        "AliasName"  = "Expand-DbaTLogResponsibly"
        "Definition" = "Expand-DbaDbLogFile"
    },
    @{
        "AliasName"  = "Test-DbaRecoveryModel"
        "Definition" = "Test-DbaDbRecoveryModel"
    }
)

$script:renames | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}


# Leave forever
@(
    @{
        "AliasName"  = "Attach-DbaDatabase"
        "Definition" = "Mount-DbaDatabase"
    },
    @{
        "AliasName"  = "Detach-DbaDatabase"
        "Definition" = "Dismount-DbaDatabase"
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
