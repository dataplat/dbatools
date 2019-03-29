$start = Get-Date

if (($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Keys -contains "Platform" -and $PSVersionTable.Platform -eq "Win32NT")) {
    $script:isWindows = $true
} else {
    $script:isWindows = $false
}

if ($PSVersionTable.PSVersion.Major -lt 3) {
    # requires doesnt work on modules
    throw "This module only supports PowerShell v3 and above"
}

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

    if ($script:doDotSource) {
        . (Resolve-Path -Path $Path)
    } else {
        $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path -Path $Path).ProviderPath))), $null, $null)
    }
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
    } else {
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

if (($PSVersionTable.Keys -contains "PSEdition") -and ($PSVersionTable.PSEdition -ne 'Desktop')) {
    $script:core = $true
} else {
    $script:core = $false
}

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
if ((Test-Path -Path "$script:PSModuleRoot\.git") -or $dbatools_enabledebug) { $script:multiFileImport = $true; $script:serialImport = $true }
if ((Test-Path -Path "$script:PSModuleRoot/.git") -or $dbatools_enabledebug) { $script:multiFileImport = $true; $script:serialImport = $true }
#endregion Multi File Import

Write-ImportTime -Text "Validated defines"
#endregion Import Defines

if (($PSVersionTable.PSVersion.Major -le 5) -or $script:isWindows) {
    Get-ChildItem -Path (Resolve-Path "$script:PSModuleRoot\bin\") -Filter "*.dll" -Recurse | Unblock-File -ErrorAction Ignore
    Write-ImportTime -Text "Unblocking Files"
}


$script:DllRoot = (Resolve-Path -Path "$script:PSModuleRoot\bin\").ProviderPath

<#
# Removed this because it doesn't seem to work well xplat and on win7 and it doesn't provide enough value
# Define folder in which to copy dll files before importing
if (-not $script:copyDllMode) { $script:DllRoot = (Resolve-Path "$script:PSModuleRoot\bin\") }
else {
    $libraryTempPath = (Resolve-Path "$($env:TEMP)\dbatools-$(Get-Random -Minimum 1000000 -Maximum 9999999)")
    while (Test-Path -Path $libraryTempPath) {
        $libraryTempPath = (Resolve-Path "$($env:TEMP)\dbatools-$(Get-Random -Minimum 1000000 -Maximum 9999999)")
    }
    $script:DllRoot = $libraryTempPath
    $null = New-Item -Path $libraryTempPath -ItemType Directory
}
#>

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

if ($script:multiFileImport) {
    # All internal functions privately available within the toolset
    foreach ($function in (Get-ChildItem -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\functions\") -Recurse | Where-Object Extension -EQ '.ps1')) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"

    . Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\cmdlets.ps1")
    Write-ImportTime -Text "Registering cmdlets"

    # All exported functions
    foreach ($function in (Get-ChildItem -Path (Resolve-Path -Path "$script:PSModuleRoot\functions\") -Recurse | Where-Object Extension -EQ '.ps1')) {
        . Import-ModuleFile $function.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"

} else {
    . (Resolve-Path -Path "$script:PSModuleRoot\allcommands.ps1")
    Write-ImportTime -Text "Loading Public and Private Commands"

    . Import-ModuleFile (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\cmdlets.ps1")
    Write-ImportTime -Text "Registering cmdlets"
}

# Load configuration system
# Should always go after library and path setting
. Import-ModuleFile "$script:PSModuleRoot\internal\configurations\configuration.ps1"
Write-ImportTime -Text "Configuration System"

# Resolving the path was causing trouble when it didn't exist yet
# Not converting the path separators based on OS was also an issue.
if (-not ([Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = Join-DbaPath $script:AppData "PowerShell" "dbatools"
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem -Path (Resolve-Path -Path "$script:PSModuleRoot\optional\*.ps1"))) {
    . Import-ModuleFile $function.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\insertTepp.ps1")
Write-ImportTime -Text "Loading TEPP"


# Process transforms
. Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\message-transforms.ps1")
Write-ImportTime -Text "Loading Message Transforms"

# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\logfilescript.ps1")
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\updateTeppAsync.ps1")
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. Import-ModuleFile -Path (Resolve-Path -Path "$script:PSModuleRoot\internal\scripts\dbatools-maintenance.ps1")
Write-ImportTime -Text "Script: Maintenance"

#region Aliases
# I renamed this function to be more accurate - 1ms
# changed to a script var so it can be used in the Rename-DbatoolsCommand
$script:renames = @(
    @{
        "AliasName"  = "Copy-SqlAgentCategory"
        "Definition" = "Copy-DbaAgentJobCategory"
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
        "Definition" = "Copy-DbaCmsRegServer"
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
        "Definition" = "Copy-DbaXESession"
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
        "Definition" = "Copy-DbaAgentProxy"
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
        "Definition" = "Copy-DbaAgentSchedule"
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
        "Definition" = "Remove-DbaDbOrphanUser"
    },
    @{
        "AliasName"  = "Repair-SqlOrphanUser"
        "Definition" = "Repair-DbaDbOrphanUser"
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
    },
    @{
        "AliasName"  = "Copy-DbaAgentCategory"
        "Definition" = "Copy-DbaAgentJobCategory"
    },
    @{
        "AliasName"  = "Copy-DbaAgentProxyAccount"
        "Definition" = "Copy-DbaAgentProxy"
    },
    @{
        "AliasName"  = "Copy-DbaAgentSharedSchedule"
        "Definition" = "Copy-DbaAgentSchedule"
    },
    @{
        "AliasName"  = "Copy-DbaCentralManagementServer"
        "Definition" = "Copy-DbaCmsRegServer"
    },
    @{
        "AliasName"  = "Copy-DbaExtendedEvent"
        "Definition" = "Copy-DbaXESession"
    },
    @{
        "AliasName"  = "Copy-DbaQueryStoreConfig"
        "Definition" = "Copy-DbaDbQueryStoreOption"
    },
    @{
        "AliasName"  = "Import-DbaCsvToSql"
        "Definition" = "Import-DbaCsv"
    },
    @{
        "AliasName"  = "Set-DbaJobOwner"
        "Definition" = "Set-DbaAgentJobOwner"
    },
    @{
        "AliasName"  = "Get-DbaOrphanUser"
        "Definition" = "Get-DbaDbOrphanUser"
    },
    @{
        "AliasName"  = "Remove-DbaOrphanUser"
        "Definition" = "Remove-DbaDbOrphanUser"
    },
    @{
        "AliasName"  = "Repair-DbaOrphanUser"
        "Definition" = "Repair-DbaDbOrphanUser"
    },
    @{
        "AliasName"  = "Test-DbaJobOwner"
        "Definition" = "Test-DbaAgentJobOwner"
    }
)

$script:renames | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}


# Leave forever
$forever = @(
    @{
        "AliasName"  = "Write-DbaDataTable"
        "Definition" = "Write-DbaDbTableData"
    },
    @{
        "AliasName"  = "Attach-DbaDatabase"
        "Definition" = "Mount-DbaDatabase"
    },
    @{
        "AliasName"  = "Detach-DbaDatabase"
        "Definition" = "Dismount-DbaDatabase"
    },
    @{
        "AliasName"  = "Get-DbaRegisteredServer"
        "Definition" = "Get-DbaCmsRegServer"
    }
)
$forever | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}
#endregion Aliases

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

# region Commands
$script:xplat = @(
    'Start-DbaMigration',
    'Copy-DbaDatabase',
    'Copy-DbaLogin',
    'Copy-DbaAgentServer',
    'Copy-DbaSpConfigure',
    'Copy-DbaDbMail',
    'Copy-DbaDbAssembly',
    'Copy-DbaAgentSchedule',
    'Copy-DbaAgentOperator',
    'Copy-DbaAgentJob',
    'Copy-DbaCustomError',
    'Copy-DbaServerAuditSpecification',
    'Copy-DbaEndpoint',
    'Copy-DbaServerAudit',
    'Copy-DbaServerRole',
    'Copy-DbaResourceGovernor',
    'Copy-DbaXESession',
    'Copy-DbaServerTrigger',
    'Copy-DbaCmsRegServer',
    'Copy-DbaSysDbUserObject',
    'Copy-DbaAgentProxy',
    'Copy-DbaAgentAlert',
    'Copy-DbaStartupProcedure',
    'Get-DbaDetachedDatabaseInfo',
    'Restore-DbaBackupFromDirectory',
    'Copy-DbaAgentJobCategory',
    'Test-DbaPath',
    'Export-DbaLogin',
    'Watch-DbaDbLogin',
    'Expand-DbaDbLogFile',
    'Test-DbaMigrationConstraint',
    'Test-DbaNetworkLatency',
    'Find-DbaDuplicateIndex',
    'Remove-DbaDatabaseSafely',
    'Set-DbaTempdbConfig',
    'Test-DbaTempdbConfig',
    'Repair-DbaDbOrphanUser',
    'Remove-DbaDbOrphanUser',
    'Find-DbaDbUnusedIndex',
    'Get-DbaDbSpace',
    'Test-DbaDbOwner',
    'Set-DbaDbOwner',
    'Test-DbaAgentJobOwner',
    'Set-DbaAgentJobOwner',
    'Test-DbaDbVirtualLogFile',
    'Get-DbaDbRestoreHistory',
    'Get-DbaTcpPort',
    'Test-DbaDbCompatibility',
    'Test-DbaDbCollation',
    'Test-DbaConnectionAuthScheme',
    'Test-DbaServerName',
    'Repair-DbaServerName',
    'Stop-DbaProcess',
    'Find-DbaOrphanedFile',
    'Get-DbaAvailabilityGroup',
    'Get-DbaLastGoodCheckDb',
    'Get-DbaProcess',
    'Get-DbaRunningJob',
    'Set-DbaMaxDop',
    'Test-DbaDbRecoveryModel',
    'Test-DbaMaxDop',
    'Remove-DbaBackup',
    'Get-DbaPermission',
    'Get-DbaLastBackup',
    'Connect-DbaInstance',
    'Get-DbaBackupHistory',
    'Read-DbaBackupHeader',
    'Test-DbaLastBackup',
    'Get-DbaMaxMemory',
    'Set-DbaMaxMemory',
    'Get-DbaDbSnapshot',
    'Remove-DbaDbSnapshot',
    'Get-DbaDbRoleMember',
    'Get-DbaServerRoleMember',
    'Resolve-DbaNetworkName',
    'Export-DbaAvailabilityGroup',
    'Write-DbaDbTableData',
    'New-DbaDbSnapshot',
    'Restore-DbaDbSnapshot',
    'Get-DbaServerTrigger',
    'Get-DbaDbTrigger',
    'Get-DbaDbState',
    'Set-DbaDbState',
    'Get-DbaHelpIndex',
    'Get-DbaAgentAlert',
    'Get-DbaAgentOperator',
    'Get-DbaSpConfigure',
    'Rename-DbaLogin',
    'Find-DbaAgentJob',
    'Find-DbaDatabase',
    'Get-DbaXESession',
    'Test-DbaOptimizeForAdHoc',
    'Find-DbaStoredProcedure',
    'Measure-DbaBackupThroughput',
    'Get-DbaDatabase',
    'Find-DbaUserObject',
    'Get-DbaDependency',
    'Find-DbaCommand',
    'Backup-DbaDatabase',
    'New-DbaDirectory',
    'Get-DbaDbQueryStoreOption',
    'Set-DbaDbQueryStoreOption',
    'Restore-DbaDatabase',
    'Copy-DbaDbQueryStoreOption',
    'Get-DbaExecutionPlan',
    'Export-DbaExecutionPlan',
    'Set-DbaSpConfigure',
    'Test-DbaIdentityUsage',
    'Get-DbaDbAssembly',
    'Get-DbaAgentJob',
    'Get-DbaCustomError',
    'Get-DbaCredential',
    'Get-DbaBackupDevice',
    'Get-DbaAgentProxy',
    'Get-DbaDbEncryption',
    'Remove-DbaDatabase',
    'Get-DbaQueryExecutionTime',
    'Get-DbaTempdbUsage',
    'Find-DbaDbGrowthEvent',
    'Test-DbaLinkedServerConnection',
    'Get-DbaDbFile',
    'Read-DbaTransactionLog',
    'Get-DbaDbTable',
    'Invoke-DbaDbShrink',
    'Get-DbaEstimatedCompletionTime',
    'Get-DbaLinkedServer',
    'New-DbaAgentJob',
    'Get-DbaLogin',
    'New-DbaScriptingOption',
    'Save-DbaDiagnosticQueryScript',
    'Invoke-DbaDiagnosticQuery',
    'Export-DbaDiagnosticQuery',
    'Invoke-DbaWhoIsActive',
    'Set-DbaAgentJob',
    'Remove-DbaAgentJob',
    'New-DbaAgentJobStep',
    'Set-DbaAgentJobStep',
    'Remove-DbaAgentJobStep',
    'New-DbaAgentSchedule',
    'Set-DbaAgentSchedule',
    'Remove-DbaAgentSchedule',
    'Backup-DbaDbCertificate',
    'Get-DbaDbCertificate',
    'Get-DbaEndpoint',
    'Get-DbaDbMasterKey',
    'Get-DbaSchemaChangeHistory',
    'Get-DbaServerAudit',
    'Get-DbaServerAuditSpecification',
    'Get-DbaProductKey',
    'Get-DbatoolsLog',
    'Restore-DbaDbCertificate',
    'New-DbaDbCertificate',
    'New-DbaDbMasterKey',
    'New-DbaServiceMasterKey',
    'Remove-DbaDbCertificate',
    'Remove-DbaDbMasterKey',
    'New-DbaConnectionStringBuilder',
    'Get-DbaInstanceProperty',
    'Get-DbaInstanceUserOption',
    'New-DbaConnectionString',
    'Get-DbaAgentSchedule',
    'Read-DbaTraceFile',
    'Get-DbaServerInstallDate',
    'Backup-DbaDbMasterKey',
    'Get-DbaAgentJobHistory',
    'Get-DbaMaintenanceSolutionLog',
    'Invoke-DbaDbLogShipRecovery',
    'Find-DbaTrigger',
    'Find-DbaView',
    'Invoke-DbaDbUpgrade',
    'Get-DbaDbUser',
    'Get-DbaAgentLog',
    'Get-DbaDbMailLog',
    'Get-DbaDbMailHistory',
    'Get-DbaDbView',
    'Get-DbaDbUdf',
    'Get-DbaDbPartitionFunction',
    'Get-DbaDbPartitionScheme',
    'Get-DbaDefaultPath',
    'Get-DbaDbStoredProcedure',
    'Test-DbaDbCompression',
    'Mount-DbaDatabase',
    'Dismount-DbaDatabase',
    'Get-DbaAgReplica',
    'Get-DbaAgDatabase',
    'Get-DbaModule',
    'Sync-DbaLoginPermission',
    'New-DbaCredential',
    'Get-DbaFile',
    'Set-DbaDbCompression',
    'Get-DbaTraceFlag',
    'Invoke-DbaCycleErrorLog',
    'Get-DbaAvailableCollation',
    'Get-DbaUserPermission',
    'Get-DbaAgHadr',
    'Find-DbaSimilarTable',
    'Get-DbaTrace',
    'Get-DbaSuspectPage',
    'Get-DbaWaitStatistic',
    'Clear-DbaWaitStatistics',
    'Get-DbaTopResourceUsage',
    'New-DbaLogin',
    'Get-DbaAgListener',
    'Invoke-DbaDbClone',
    'Disable-DbaTraceFlag',
    'Enable-DbaTraceFlag',
    'Start-DbaAgentJob',
    'Stop-DbaAgentJob',
    'New-DbaAgentProxy',
    'Test-DbaDbLogShipStatus',
    'Get-DbaXESessionTarget',
    'New-DbaXESmartTargetResponse',
    'New-DbaXESmartTarget',
    'Get-DbaDbVirtualLogFile',
    'Get-DbaBackupInformation',
    'Start-DbaXESession',
    'Stop-DbaXESession',
    'Set-DbaDbRecoveryModel',
    'Get-DbaDbRecoveryModel',
    'Get-DbaWaitingTask',
    'Remove-DbaDbUser',
    'Get-DbaDump',
    'Invoke-DbaAdvancedRestore',
    'Format-DbaBackupInformation',
    'Get-DbaAgentJobStep',
    'Test-DbaBackupInformation',
    'Invoke-DbaBalanceDataFiles',
    'Select-DbaBackupInformation',
    'Publish-DbaDacPackage',
    'Copy-DbaDbTableData',
    'Invoke-DbaQuery',
    'Remove-DbaLogin',
    'Get-DbaAgentJobCategory',
    'New-DbaAgentJobCategory',
    'Remove-DbaAgentJobCategory',
    'Set-DbaAgentJobCategory',
    'Get-DbaDbRole',
    'Get-DbaServerRole',
    'Find-DbaBackup',
    'Remove-DbaXESession',
    'New-DbaXESession',
    'Get-DbaXEStore',
    'New-DbaXESmartTableWriter',
    'New-DbaXESmartReplay',
    'New-DbaXESmartEmail',
    'New-DbaXESmartQueryExec',
    'Start-DbaXESmartTarget',
    'Get-DbaDbOrphanUser',
    'Get-DbaOpenTransaction',
    'Get-DbaDbLogShipError',
    'Test-DbaBuild',
    'Get-DbaXESessionTemplate',
    'ConvertTo-DbaXESession',
    'Start-DbaTrace',
    'Stop-DbaTrace',
    'Remove-DbaTrace',
    'Set-DbaLogin',
    'Copy-DbaXESessionTemplate',
    'Get-DbaXEObject',
    'ConvertTo-DbaDataTable',
    'Find-DbaDisabledIndex',
    'Get-DbaXESmartTarget',
    'Remove-DbaXESmartTarget',
    'Stop-DbaXESmartTarget',
    'Get-DbaCmsRegServerGroup',
    'New-DbaDbUser',
    'Measure-DbaDiskSpaceRequirement',
    'New-DbaXESmartCsvWriter',
    'Invoke-DbaXeReplay',
    'Find-DbaInstance',
    'Test-DbaDiskSpeed',
    'Get-DbaDbExtentDiff',
    'Read-DbaAuditFile',
    'Get-DbaDbCompression',
    'Invoke-DbaDbDecryptObject',
    'Get-DbaDbForeignKey',
    'Get-DbaDbCheckConstraint',
    'Set-DbaAgentAlert',
    'Get-DbaWaitResource',
    'Get-DbaDbPageInfo',
    'Get-DbaConnection',
    'Test-DbaLoginPassword',
    'Get-DbaErrorLogConfig',
    'Set-DbaErrorLogConfig',
    'Get-DbaPlanCache',
    'Clear-DbaPlanCache',
    'ConvertTo-DbaTimeline',
    'Get-DbaDbMail',
    'Get-DbaDbMailAccount',
    'Get-DbaDbMailProfile',
    'Get-DbaDbMailConfig',
    'Get-DbaDbMailServer',
    'New-DbaDbMailServer',
    'New-DbaDbMailAccount',
    'New-DbaDbMailProfile',
    'Get-DbaResourceGovernor',
    'Get-DbaRgResourcePool',
    'Get-DbaRgWorkloadGroup',
    'Get-DbaRgClassifierFunction',
    'Export-DbaInstance',
    'Invoke-DbatoolsRenameHelper',
    'Measure-DbatoolsImport',
    'Get-DbaDeprecatedFeature',
    'Test-DbaDeprecatedFeature'
    'Get-DbaDbFeatureUsage',
    'Stop-DbaEndpoint',
    'Start-DbaEndpoint',
    'Set-DbaDbMirror',
    'Repair-DbaDbMirror',
    'Remove-DbaEndpoint',
    'Remove-DbaDbMirrorMonitor',
    'Remove-DbaDbMirror',
    'New-DbaEndpoint',
    'Invoke-DbaDbMirroring',
    'Invoke-DbaDbMirrorFailover',
    'Get-DbaDbMirrorMonitor',
    'Get-DbaDbMirror',
    'Add-DbaDbMirrorMonitor',
    'Test-DbaEndpoint',
    'Get-DbaDbSharePoint',
    'Get-DbaDbMemoryUsage',
    'Clear-DbaLatchStatistics',
    'Get-DbaCpuRingBuffer',
    'Get-DbaIoLatency',
    'Get-DbaLatchStatistic',
    'Get-DbaSpinLockStatistic',
    'Add-DbaAgDatabase',
    'Add-DbaAgListener',
    'Add-DbaAgReplica',
    'Grant-DbaAgPermission',
    'Invoke-DbaAgFailover',
    'Join-DbaAvailabilityGroup',
    'New-DbaAvailabilityGroup',
    'Remove-DbaAgDatabase',
    'Remove-DbaAgListener',
    'Remove-DbaAvailabilityGroup',
    'Revoke-DbaAgPermission',
    'Get-DbaDbCompatibility',
    'Set-DbaDbCompatibility',
    'Invoke-DbatoolsFormatter',
    'Remove-DbaAgReplica',
    'Resume-DbaAgDbDataMovement',
    'Set-DbaAgListener',
    'Set-DbaAgReplica',
    'Set-DbaAvailabilityGroup',
    'Set-DbaEndpoint',
    'Suspend-DbaAgDbDataMovement',
    'Sync-DbaAvailabilityGroup',
    'Get-DbaMemoryCondition',
    'Remove-DbaDbBackupRestoreHistory',
    'New-DbaDatabase'
    'New-DbaDacOption',
    'Get-DbaDbccHelp',
    'Get-DbaDbccMemoryStatus',
    'Get-DbaDbccProcCache',
    'Get-DbaDbccUserOption',
    'Get-DbaAgentServer',
    'Set-DbaAgentServer',
    'Invoke-DbaDbccFreeCache'
    'Export-DbatoolsConfig',
    'Import-DbatoolsConfig',
    'Reset-DbatoolsConfig',
    'Unregister-DbatoolsConfig',
    'Join-DbaPath',
    'Resolve-DbaPath',
    'Import-DbaCsv',
    'Invoke-DbaDbDataMasking',
    'New-DbaDbMaskingConfig',
    'Get-DbaDbccSessionBuffer',
    'Get-DbaDbccStatistic',
    'Get-DbaDbDbccOpenTran',
    'Invoke-DbaDbccDropCleanBuffer',
    'Invoke-DbaDbDbccCheckConstraint',
    'Invoke-DbaDbDbccCleanTable',
    'Invoke-DbaDbDbccUpdateUsage',
    'Get-DbaDbIdentity',
    'Set-DbaDbIdentity',
    'Get-DbaCmsRegServer',
    'Get-DbaCmsRegServerStore',
    'Add-DbaCmsRegServer',
    'Add-DbaCmsRegServerGroup',
    'Export-DbaCmsRegServer',
    'Import-DbaCmsRegServer',
    'Move-DbaCmsRegServer',
    'Move-DbaCmsRegServerGroup',
    'Remove-DbaCmsRegServer',
    'Remove-DbaCmsRegServerGroup',
    # Config system
    'Get-DbatoolsConfig',
    'Get-DbatoolsConfigValue',
    'Set-DbatoolsConfig',
    'Register-DbatoolsConfig',
    # Data generator
    'New-DbaDbDataGeneratorConfig',
    'Invoke-DbaDbDataGenerator',
    'Get-DbaRandomizedValue',
    'Get-DbaRandomizedDatasetTemplate',
    'Get-DbaRandomizedDataset',
    'Get-DbaRandomizedType',
    'Export-DbaDbTableData'
)

$script:noncoresmo = @(
    # SMO issues
    'Export-DbaUser',
    'Get-DbaSsisExecutionHistory',
    'Get-DbaRepDistributor',
    'Copy-DbaPolicyManagement',
    'Copy-DbaDataCollector',
    'Copy-DbaSsisCatalog',
    'New-DbaSsisCatalog',
    'Get-DbaSsisEnvironmentVariable',
    'Get-DbaPbmCategory',
    'Get-DbaPbmCategorySubscription',
    'Get-DbaPbmCondition',
    'Get-DbaPbmObjectSet',
    'Get-DbaPbmPolicy',
    'Get-DbaPbmStore',
    'Get-DbaRepPublication',
    'Test-DbaRepLatency',
    'Export-DbaRepServerSetting',
    'Get-DbaRepServer'
)
$script:windowsonly = @(
    # solvable filesystem issues or other workarounds
    'Copy-DbaBackupDevice',
    'Install-DbaSqlWatch',
    'Uninstall-DbaSqlWatch',
    'Get-DbaRegistryRoot',
    'Install-DbaMaintenanceSolution',
    'New-DbatoolsSupportPackage',
    'Export-DbaScript',
    'Get-DbaAgentJobOutputFile',
    'Set-DbaAgentJobOutputFile',
    'Get-DbaBuildReference',
    'New-DbaDacProfile'
    'Import-DbaXESessionTemplate',
    'Export-DbaXESessionTemplate',
    'Import-DbaSpConfigure',
    'Export-DbaSpConfigure'
    'Update-Dbatools',
    'Install-DbaWhoIsActive',
    'Install-DbaFirstResponderKit',
    'Read-DbaXEFile',
    'Watch-DbaXESession',
    'Test-DbaMaxMemory', # can be fixed by not testing remote when linux is detected
    'Rename-DbaDatabase', # can maybebe fixed by not remoting when linux is detected
    # CM and Windows functions
    'Install-DbaInstance',
    'Invoke-DbaAdvancedInstall',
    'Update-DbaInstance',
    'Invoke-DbaAdvancedUpdate',
    'Invoke-DbaPfRelog',
    'Get-DbaPfDataCollectorCounter',
    'Get-DbaPfDataCollectorCounterSample',
    'Get-DbaPfDataCollector',
    'Get-DbaPfDataCollectorSet',
    'Start-DbaPfDataCollectorSet',
    'Stop-DbaPfDataCollectorSet',
    'Export-DbaPfDataCollectorSetTemplate',
    'Get-DbaPfDataCollectorSetTemplate',
    'Import-DbaPfDataCollectorSetTemplate',
    'Remove-DbaPfDataCollectorSet',
    'Add-DbaPfDataCollectorCounter',
    'Remove-DbaPfDataCollectorCounter',
    'Get-DbaPfAvailableCounter',
    'Export-DbaXECsv',
    'Get-DbaOperatingSystem',
    'Get-DbaComputerSystem',
    'Set-DbaPrivilege',
    'Set-DbaTcpPort',
    'Set-DbaCmConnection',
    'Get-DbaUptime',
    'Get-DbaMemoryUsage',
    'Clear-DbaConnectionPool',
    'Get-DbaLocaleSetting',
    'Get-DbaFilestream',
    'Enable-DbaFilestream',
    'Disable-DbaFilestream',
    'Get-DbaCpuUsage',
    'Get-DbaPowerPlan',
    'Get-DbaWsfcAvailableDisk',
    'Get-DbaWsfcCluster',
    'Get-DbaWsfcDisk',
    'Get-DbaWsfcNetwork',
    'Get-DbaWsfcNetworkInterface',
    'Get-DbaWsfcNode',
    'Get-DbaWsfcResource',
    'Get-DbaWsfcResourceType',
    'Get-DbaWsfcRole',
    'Get-DbaWsfcSharedVolume',
    'Export-DbaCredential',
    'Export-DbaLinkedServer',
    'Get-DbaFeature',
    'Update-DbaServiceAccount',
    'Remove-DbaClientAlias',
    'Disable-DbaAgHadr',
    'Enable-DbaAgHadr',
    'Stop-DbaService',
    'Start-DbaService',
    'Restart-DbaService',
    'New-DbaClientAlias',
    'Get-DbaClientAlias',
    'Remove-DbaNetworkCertificate',
    'Enable-DbaForceNetworkEncryption',
    'Disable-DbaForceNetworkEncryption',
    'Get-DbaForceNetworkEncryption',
    'Remove-DbaComputerCertificate',
    'New-DbaComputerCertificate',
    'Get-DbaComputerCertificate',
    'Add-DbaComputerCertificate',
    'Get-DbaNetworkCertificate',
    'Set-DbaNetworkCertificate',
    'Invoke-DbaDbLogShipping',
    'New-DbaCmConnection',
    'Get-DbaCmConnection',
    'Remove-DbaCmConnection',
    'Test-DbaCmConnection',
    'Get-DbaCmObject',
    'Set-DbaStartupParameter',
    'Get-DbaNetworkActivity',
    'Get-DbaServerProtocol'
    'Watch-DbaUpdate',
    'Uninstall-DbaWatchUpdate',
    'Install-DbaWatchUpdate',
    'Get-DbaPrivilege',
    'Get-DbaMsdtc',
    'Get-DbaPageFileSetting',
    'Copy-DbaCredential',
    'Test-DbaConnection',
    'Reset-DbaAdmin',
    'Copy-DbaLinkedServer',
    'Get-DbaDiskSpace',
    'Test-DbaDiskAllocation',
    'Test-DbaPowerPlan',
    'Set-DbaPowerPlan',
    'Test-DbaDiskAlignment',
    'Get-DbaStartupParameter',
    'Get-DbaSpn',
    'Test-DbaSpn',
    'Set-DbaSpn',
    'Remove-DbaSpn',
    'Get-DbaService',
    'Get-DbaClientProtocol',
    'Get-DbaWindowsLog',
    # WPF
    'Show-DbaServerFileSystem',
    'Show-DbaDbList',
    # AD?
    'Test-DbaWindowsLogin',
    'Find-DbaLoginInGroup',
    # 3rd party non-core DLL or exe
    'Export-DbaDacPackage', # relies on sqlpackage.exe
    # Unknown
    'Get-DbaErrorLog',
    'Get-DbaManagementObject',
    'Test-DbaManagementObject'
)

# If a developer or appveyor calls the psm1 directly, they want all functions
# So do not explicity export because everything else is then implicity excluded
if (-not $script:multiFileImport) {
    if (($PSVersionTable.Keys -contains "Platform")) {
        if ($PSVersionTable.Platform -ne "Win32NT") {
            Export-ModuleMember -Function $script:xplat
        } else {
            Export-ModuleMember -Function $script:xplat
            Export-ModuleMember -Function $script:windowsonly
        }
    } else {
        Export-ModuleMember -Function $script:xplat
        Export-ModuleMember -Function $script:windowsonly
        Export-ModuleMember -Function $script:noncoresmo
    }

    Export-ModuleMember -Alias $script:renames
    Export-ModuleMember -Alias $forever

    Export-ModuleMember -Cmdlet Select-DbaObject, Set-DbatoolsConfig

    Write-ImportTime -Text "Exported module member"
}

$timeout = 20000
$timeSpent = 0
while ($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') {
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
        break
    }
}

if ($script:smoRunspace) {
    $script:smoRunspace.Runspace.Close()
    $script:smoRunspace.Runspace.Dispose()
    $script:smoRunspace.Dispose()
    Remove-Variable -Name smoRunspace -Scope script
}
Write-ImportTime -Text "Waiting for runspaces to finish"

if ($PSCommandPath -like "*.psm1") {
    Update-TypeData -AppendPath (Resolve-Path -Path "$script:PSModuleRoot\xml\dbatools.Types.ps1xml")
    Write-ImportTime -Text "Loaded type extensions"
}
#. Import-ModuleFile "$script:PSModuleRoot\bin\type-extensions.ps1"
#Write-ImportTime -Text "Loaded type extensions"

[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true;

if (Get-Module -Name sqlserver, sqlps) {
    if (Get-DbatoolsConfigValue -FullName Import.SqlpsCheck) {
        Write-Warning -Message 'SQLPS or SqlServer was previously imported during this session. If you encounter weird issues with dbatools, please restart PowerShell, then import dbatools without loading SQLPS or SqlServer first.'
        Write-Warning -Message 'To disable this message, type: Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig'
    }
}

#endregion Post-Import Cleanup