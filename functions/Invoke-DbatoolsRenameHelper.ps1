function Invoke-DbatoolsRenameHelper {
    <#
    .SYNOPSIS
        Older dbatools command names have been changed. This script helps keep up.

    .DESCRIPTION
        Older dbatools command names have been changed. This script helps keep up.

    .PARAMETER InputObject
        A piped in object from Get-ChildItem

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsRenameHelper

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper

        Checks to see if any ps1 file in C:\temp\ps matches an old command name.
        If so, then the command name within the text is updated and the resulting changes are written to disk in UTF-8.

    .EXAMPLE
        PS C:\> Get-ChildItem C:\temp\ps\*.ps1 -Recurse | Invoke-DbatoolsRenameHelper -Encoding Ascii -WhatIf

        Shows what would happen if the command would run. If the command would run and there were matches,
        the resulting changes would be written to disk as Ascii encoded.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $paramrenames = @{
            ExcludeAllSystemDb = 'ExcludeSystem'
            ExcludeAllUserDb   = 'ExcludeUser'
            'Invoke-Sqlcmd2'   = 'Invoke-DbaQuery'
            NetworkShare       = 'SharedPath'
            NoDatabases        = 'ExcludeDatabases'
            NoDisabledJobs     = 'ExcludeDisabledJobs'
            NoJobs             = 'ExcludeJobs'
            NoJobSteps         = 'ExcludeJobSteps'
            NoQueryTextColumn  = 'ExcludeQueryTextColumn'
            NoSystem           = 'ExcludeSystemLogins'
            NoSystemDb         = 'ExcludeSystem'
            NoSystemLogins     = 'ExcludeSystemLogins'
            NoSystemObjects    = 'ExcludeSystemObjects'
            NoSystemSpid       = 'ExcludeSystemSpids'
            UseLastBackups     = 'UseLastBackup'
            PasswordExpiration = 'PasswordExpirationEnabled'
            PasswordPolicy     = 'PasswordPolicyEnforced'
            ServerInstance     = 'SqlInstance'
        }

        $commandrenames = @{
            'Find-DbaDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-DbaDisabledIndex'             = 'Find-DbaDbDisabledIndex'
            'Add-DbaRegisteredServer'           = 'Add-DbaRegServer'
            'Add-DbaRegisteredServerGroup'      = 'Add-DbaRegServerGroup'
            'Backup-DbaDatabaseCertificate'     = 'Backup-DbaDbCertificate'
            'Backup-DbaDatabaseMasterKey'       = 'Backup-DbaDbMasterKey'
            'Clear-DbaSqlConnectionPool'        = 'Clear-DbaConnectionPool'
            'Connect-DbaServer'                 = 'Connect-DbaInstance'
            'Copy-DbaAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-DbaAgentProxyAccount'         = 'Copy-DbaAgentProxy'
            'Copy-DbaAgentSharedSchedule'       = 'Copy-DbaAgentSchedule'
            'Copy-DbaCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-DbaDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-DbaDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-DbaExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-DbaQueryStoreConfig'          = 'Copy-DbaDbQueryStoreOption'
            'Copy-DbaSqlDataCollector'          = 'Copy-DbaDataCollector'
            'Copy-DbaSqlPolicyManagement'       = 'Copy-DbaPolicyManagement'
            'Copy-DbaSqlServerAgent'            = 'Copy-DbaAgentServer'
            'Copy-DbaTableData'                 = 'Copy-DbaDbTableData'
            'Copy-SqlAgentCategory'             = 'Copy-DbaAgentJobCategory'
            'Copy-SqlAlert'                     = 'Copy-DbaAgentAlert'
            'Copy-SqlAudit'                     = 'Copy-DbaInstanceAudit'
            'Copy-SqlAuditSpecification'        = 'Copy-DbaInstanceAuditSpecification'
            'Copy-SqlBackupDevice'              = 'Copy-DbaBackupDevice'
            'Copy-SqlCentralManagementServer'   = 'Copy-DbaRegServer'
            'Copy-SqlCredential'                = 'Copy-DbaCredential'
            'Copy-SqlCustomError'               = 'Copy-DbaCustomError'
            'Copy-SqlDatabase'                  = 'Copy-DbaDatabase'
            'Copy-SqlDatabaseAssembly'          = 'Copy-DbaDbAssembly'
            'Copy-SqlDatabaseMail'              = 'Copy-DbaDbMail'
            'Copy-SqlDataCollector'             = 'Copy-DbaDataCollector'
            'Copy-SqlEndpoint'                  = 'Copy-DbaEndpoint'
            'Copy-SqlExtendedEvent'             = 'Copy-DbaXESession'
            'Copy-SqlJob'                       = 'Copy-DbaAgentJob'
            'Copy-SqlJobServer'                 = 'Copy-SqlInstanceAgent'
            'Copy-SqlLinkedServer'              = 'Copy-DbaLinkedServer'
            'Copy-SqlLogin'                     = 'Copy-DbaLogin'
            'Copy-SqlOperator'                  = 'Copy-DbaAgentOperator'
            'Copy-SqlPolicyManagement'          = 'Copy-DbaPolicyManagement'
            'Copy-SqlProxyAccount'              = 'Copy-DbaAgentProxy'
            'Copy-SqlResourceGovernor'          = 'Copy-DbaResourceGovernor'
            'Copy-SqlInstanceAgent'             = 'Copy-DbaAgentServer'
            'Copy-SqlInstanceTrigger'           = 'Copy-DbaInstanceTrigger'
            'Copy-SqlSharedSchedule'            = 'Copy-DbaAgentSchedule'
            'Copy-SqlSpConfigure'               = 'Copy-DbaSpConfigure'
            'Copy-SqlSsisCatalog'               = 'Copy-DbaSsisCatalog'
            'Copy-SqlSysDbUserObjects'          = 'Copy-DbaSysDbUserObject'
            'Copy-SqlUserDefinedMessage'        = 'Copy-SqlCustomError'
            'Expand-DbaTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Expand-SqlTLogResponsibly'         = 'Expand-DbaDbLogFile'
            'Export-DbaDacpac'                  = 'Export-DbaDacPackage'
            'Export-DbaRegisteredServer'        = 'Export-DbaRegServer'
            'Export-SqlLogin'                   = 'Export-DbaLogin'
            'Export-SqlSpConfigure'             = 'Export-DbaSpConfigure'
            'Export-SqlUser'                    = 'Export-DbaUser'
            'Find-DbaDatabaseGrowthEvent'       = 'Find-DbaDbGrowthEvent'
            'Find-SqlDuplicateIndex'            = 'Find-DbaDbDuplicateIndex'
            'Find-SqlUnusedIndex'               = 'Find-DbaDbUnusedIndex'
            'Get-DbaRegServerName'              = 'Get-DbaRegServer'
            'Get-DbaConfig'                     = 'Get-DbatoolsConfig'
            'Get-DbaConfigValue'                = 'Get-DbatoolsConfigValue'
            'Get-DbaDatabaseAssembly'           = 'Get-DbaDbAssembly'
            'Get-DbaDatabaseCertificate'        = 'Get-DbaDbCertificate'
            'Get-DbaDatabaseEncryption'         = 'Get-DbaDbEncryption'
            'Get-DbaDatabaseFile'               = 'Get-DbaDbFile'
            'Get-DbaDatabaseFreeSpace'          = 'Get-DbaDbSpace'
            'Get-DbaDatabaseMasterKey'          = 'Get-DbaDbMasterKey'
            'Get-DbaDatabasePartitionFunction'  = 'Get-DbaDbPartitionFunction'
            'Get-DbaDatabasePartitionScheme'    = 'Get-DbaDbPartitionScheme'
            'Get-DbaDatabaseSnapshot'           = 'Get-DbaDbSnapshot'
            'Get-DbaDatabaseSpace'              = 'Get-DbaDbSpace'
            'Get-DbaDatabaseState'              = 'Get-DbaDbState'
            'Get-DbaDatabaseUdf'                = 'Get-DbaDbUdf'
            'Get-DbaDatabaseUser'               = 'Get-DbaDbUser'
            'Get-DbaDatabaseView'               = 'Get-DbaDbView'
            'Get-DbaDbQueryStoreOptions'        = 'Get-DbaDbQueryStoreOption'
            'Get-DbaDistributor'                = 'Get-DbaRepDistributor'
            'Get-DbaInstance'                   = 'Connect-DbaInstance'
            'Get-DbaJobCategory'                = 'Get-DbaAgentJobCategory'
            'Get-DbaLog'                        = 'Get-DbaErrorLog'
            'Get-DbaLogShippingError'           = 'Get-DbaDbLogShipError'
            'Get-DbaOrphanUser'                 = 'Get-DbaDbOrphanUser'
            'Get-DbaPolicy'                     = 'Get-DbaPbmPolicy'
            'Get-DbaQueryStoreConfig'           = 'Get-DbaDbQueryStoreOption'
            'Get-DbaRegisteredServerGroup'      = 'Get-DbaRegServerGroup'
            'Get-DbaRegisteredServerStore'      = 'Get-DbaRegServerStore'
            'Get-DbaRestoreHistory'             = 'Get-DbaDbRestoreHistory'
            'Get-DbaRoleMember'                 = 'Get-DbaDbRoleMember'
            'Get-DbaSqlBuildReference'          = 'Get-DbaBuildReference'
            'Get-DbaSqlFeature'                 = 'Get-DbaFeature'
            'Get-DbaSqlInstanceProperty'        = 'Get-DbaInstanceProperty'
            'Get-DbaSqlInstanceUserOption'      = 'Get-DbaInstanceUserOption'
            'Get-DbaSqlManagementObject'        = 'Get-DbaManagementObject'
            'Get-DbaSqlModule'                  = 'Get-DbaModule'
            'Get-DbaSqlProductKey'              = 'Get-DbaProductKey'
            'Get-DbaSqlRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaSqlService'                 = 'Get-DbaService'
            'Get-DbaTable'                      = 'Get-DbaDbTable'
            'Get-DbaTraceFile'                  = 'Get-DbaTrace'
            'Get-DbaUserLevelPermission'        = 'Get-DbaUserPermission'
            'Get-DbaXEventSession'              = 'Get-DbaXESession'
            'Get-DbaXEventSessionTarget'        = 'Get-DbaXESessionTarget'
            'Get-DiskSpace'                     = 'Get-DbaDiskSpace'
            'Get-SqlMaxMemory'                  = 'Get-DbaMaxMemory'
            'Get-SqlRegisteredServerName'       = 'Get-DbaRegServer'
            'Get-SqlInstanceKey'                = 'Get-DbaProductKey'
            'Import-DbaCsvToSql'                = 'Import-DbaCsv'
            'Import-DbaRegisteredServer'        = 'Import-DbaRegServer'
            'Import-SqlSpConfigure'             = 'Import-DbaSpConfigure'
            'Install-SqlWhoIsActive'            = 'Install-DbaWhoIsActive'
            'Invoke-DbaCmd'                     = 'Invoke-DbaQuery'
            'Invoke-DbaDatabaseClone'           = 'Invoke-DbaDbClone'
            'Invoke-DbaDatabaseShrink'          = 'Invoke-DbaDbShrink'
            'Invoke-DbaDatabaseUpgrade'         = 'Invoke-DbaDbUpgrade'
            'Invoke-DbaLogShipping'             = 'Invoke-DbaDbLogShipping'
            'Invoke-DbaLogShippingRecovery'     = 'Invoke-DbaDbLogShipRecovery'
            'Invoke-DbaSqlQuery'                = 'Invoke-DbaQuery'
            'Move-DbaRegisteredServer'          = 'Move-DbaRegServer'
            'Move-DbaRegisteredServerGroup'     = 'Move-DbaRegServerGroup'
            'New-DbaDatabaseCertificate'        = 'New-DbaDbCertificate'
            'New-DbaDatabaseMasterKey'          = 'New-DbaDbMasterKey'
            'New-DbaDatabaseSnapshot'           = 'New-DbaDbSnapshot'
            'New-DbaPublishProfile'             = 'New-DbaDacProfile'
            'New-DbaSqlConnectionString'        = 'New-DbaConnectionString'
            'New-DbaSqlConnectionStringBuilder' = 'New-DbaConnectionStringBuilder'
            'New-DbaSqlDirectory'               = 'New-DbaDirectory'
            'Out-DbaDataTable'                  = 'ConvertTo-DbaDataTable'
            'Publish-DbaDacpac'                 = 'Publish-DbaDacPackage'
            'Read-DbaXEventFile'                = 'Read-DbaXEFile'
            'Register-DbaConfig'                = 'Register-DbatoolsConfig'
            'Remove-DbaDatabaseCertificate'     = 'Remove-DbaDbCertificate'
            'Remove-DbaDatabaseMasterKey'       = 'Remove-DbaDbMasterKey'
            'Remove-DbaDatabaseSnapshot'        = 'Remove-DbaDbSnapshot'
            'Remove-DbaOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Remove-DbaRegisteredServer'        = 'Remove-DbaRegServer'
            'Remove-DbaRegisteredServerGroup'   = 'Remove-DbaRegServerGroup'
            'Remove-SqlDatabaseSafely'          = 'Remove-DbaDatabaseSafely'
            'Remove-SqlOrphanUser'              = 'Remove-DbaDbOrphanUser'
            'Repair-DbaOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Repair-SqlOrphanUser'              = 'Repair-DbaDbOrphanUser'
            'Reset-SqlAdmin'                    = 'Reset-DbaAdmin'
            'Reset-SqlSaPassword'               = 'Reset-SqlAdmin'
            'Restart-DbaSqlService'             = 'Restart-DbaService'
            'Restore-DbaDatabaseCertificate'    = 'Restore-DbaDbCertificate'
            'Restore-DbaDatabaseSnapshot'       = 'Restore-DbaDbSnapshot'
            'Restore-HallengrenBackup'          = 'Restore-SqlBackupFromDirectory'
            'Set-DbaConfig'                     = 'Set-DbatoolsConfig'
            'Get-DbaBackupHistory'              = 'Get-DbaDbBackupHistory'
            'Set-DbaDatabaseOwner'              = 'Set-DbaDbOwner'
            'Set-DbaDatabaseState'              = 'Set-DbaDbState'
            'Set-DbaDbQueryStoreOptions'        = 'Set-DbaDbQueryStoreOption'
            'Set-DbaJobOwner'                   = 'Set-DbaAgentJobOwner'
            'Set-DbaQueryStoreConfig'           = 'Set-DbaDbQueryStoreOption'
            'Set-DbaTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Set-SqlMaxMemory'                  = 'Set-DbaMaxMemory'
            'Set-SqlTempDbConfiguration'        = 'Set-DbaTempdbConfig'
            'Show-DbaDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlDatabaseList'              = 'Show-DbaDbList'
            'Show-SqlMigrationConstraint'       = 'Test-SqlMigrationConstraint'
            'Show-SqlInstanceFileSystem'        = 'Show-DbaInstanceFileSystem'
            'Show-SqlWhoIsActive'               = 'Invoke-DbaWhoIsActive'
            'Start-DbaSqlService'               = 'Start-DbaService'
            'Start-SqlMigration'                = 'Start-DbaMigration'
            'Stop-DbaSqlService'                = 'Stop-DbaService'
            'Sync-DbaSqlLoginPermission'        = 'Sync-DbaLoginPermission'
            'Sync-SqlLoginPermissions'          = 'Sync-DbaLoginPermission'
            'Test-DbaDatabaseCollation'         = 'Test-DbaDbCollation'
            'Test-DbaDatabaseCompatibility'     = 'Test-DbaDbCompatibility'
            'Test-DbaDatabaseOwner'             = 'Test-DbaDbOwner'
            'Test-DbaDbVirtualLogFile'          = 'Measure-DbaDbVirtualLogFile'
            'Test-DbaFullRecoveryModel'         = 'Test-DbaDbRecoveryModel'
            'Test-DbaJobOwner'                  = 'Test-DbaAgentJobOwner'
            'Test-DbaLogShippingStatus'         = 'Test-DbaDbLogShipStatus'
            'Test-DbaRecoveryModel'             = 'Test-DbaDbRecoveryModel'
            'Test-DbaSqlBuild'                  = 'Test-DbaBuild'
            'Test-DbaSqlManagementObject'       = 'Test-DbaManagementObject'
            'Test-DbaSqlPath'                   = 'Test-DbaPath'
            'Test-DbaTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Test-DbaValidLogin'                = 'Test-DbaWindowsLogin'
            'Test-DbaVirtualLogFile'            = 'Measure-DbaDbVirtualLogFile'
            'Test-SqlConnection'                = 'Test-DbaConnection'
            'Test-SqlDiskAllocation'            = 'Test-DbaDiskAllocation'
            'Test-SqlMigrationConstraint'       = 'Test-DbaMigrationConstraint'
            'Test-SqlNetworkLatency'            = 'Test-DbaNetworkLatency'
            'Test-SqlPath'                      = 'Test-DbaPath'
            'Test-SqlTempDbConfiguration'       = 'Test-DbaTempdbConfig'
            'Update-DbaSqlServiceAccount'       = 'Update-DbaServiceAccount'
            'Watch-DbaXEventSession'            = 'Watch-DbaXESession'
            'Watch-SqlDbLogin'                  = 'Watch-DbaDbLogin'
            'Add-DbaCmsRegServer'               = 'Add-DbaRegServer'
            'Add-DbaCmsRegServerGroup'          = 'Add-DbaRegServerGroup'
            'Copy-DbaCmsRegServer'              = 'Copy-DbaRegServer'
            'Export-DbaCmsRegServer'            = 'Export-DbaRegServer'
            'Get-DbaCmsRegistryRoot'            = 'Get-DbaRegistryRoot'
            'Get-DbaCmsRegServer'               = 'Get-DbaRegServer'
            'Get-DbaCmsRegServerGroup'          = 'Get-DbaRegServerGroup'
            'Get-DbaCmsRegServerStore'          = 'Get-DbaRegServerStore'
            'Import-DbaCmsRegServer'            = 'Import-DbaRegServer'
            'Move-DbaCmsRegServer'              = 'Move-DbaRegServer'
            'Move-DbaCmsRegServerGroup'         = 'Move-DbaRegServerGroup'
            'Remove-DbaCmsRegServer'            = 'Remove-DbaRegServer'
            'Remove-DbaCmsRegServerGroup'       = 'Remove-DbaRegServerGroup'
            'Copy-DbaServerAuditSpecification'  = 'Copy-DbaInstanceAuditSpecification'
            'Copy-DbaServerAudit'               = 'Copy-DbaInstanceAudit'
            'Copy-DbaServerTrigger'             = 'Copy-DbaInstanceTrigger'
            'Test-DbaServerName'                = 'Test-DbaInstanceName'
            'Test-DbaInstanceName'              = 'Repair-DbaInstanceName'
            'Get-DbaServerTrigger'              = 'Get-DbaInstanceTrigger'
            'Get-DbaServerAudit'                = 'Get-DbaInstanceAudit'
            'Get-DbaServerAuditSpecification'   = 'Get-DbaInstanceAuditSpecification'
            'Get-DbaServerInstallDate'          = 'Get-DbaInstanceInstallDate'
            'Show-DbaServerFileSystem'          = 'Show-DbaInstanceFileSystem'
            'Install-DbaWatchUpdate'            = 'Install-DbatoolsWatchUpdate'
            'Uninstall-DbaWatchUpdate'          = 'Uninstall-DbatoolsWatchUpdate'
        }
    }
    process {
        foreach ($fileobject in $InputObject) {
            $file = $fileobject.FullName

            foreach ($name in $paramrenames.GetEnumerator()) {
                if ((Select-String -Pattern $name.Key -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = (Get-Content -Path $file -Raw).Replace($name.Key, $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }

            foreach ($name in $commandrenames.GetEnumerator()) {
                if ((Select-String -Pattern "\b$($name.Key)\b" -Path $file)) {
                    if ($Pscmdlet.ShouldProcess($file, "Replacing $($name.Key) with $($name.Value)")) {
                        $content = ((Get-Content -Path $file -Raw) -Replace "\b$($name.Key)\b", $name.Value).Trim()
                        Set-Content -Path $file -Encoding $Encoding -Value $content
                        [pscustomobject]@{
                            Path         = $file
                            Pattern      = $name.Key
                            ReplacedWith = $name.Value
                        }
                    }
                }
            }
        }
    }
}
