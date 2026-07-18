@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.database.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = '4470d634-03a2-405d-a218-0b9f327d0b69'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.database: objects inside your databases - part of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaDbState',
        'Add-DbaDbFile',
        'Add-DbaDbRoleMember',
        'Add-DbaExtendedProperty',
        'Compare-DbaDbSchema',
        'Dismount-DbaDatabase',
        'Expand-DbaDbLogFile',
        'Export-DbaBinaryFile',
        'Export-DbaDacPackage',
        'Export-DbaDbRole',
        'Export-DbaDbTableData',
        'Find-DbaDatabase',
        'Find-DbaObject',
        'Find-DbaOrphanedFile',
        'Find-DbaSimilarTable',
        'Find-DbaStoredProcedure',
        'Find-DbaTrigger',
        'Get-DbaDbCompatibility',
        'Get-DbaDbDataClassification',
        'Get-DbaDbAssembly',
        'Get-DbaBinaryFileTable',
        'Find-DbaView',
        'Get-DbaDbCompression',
        'Get-DbaDbCheckConstraint',
        'Find-DbaUserObject',
        'Get-DbaDbDetachedFileInfo',
        'Get-DbaDbFile',
        'Get-DbaDbFileGroup',
        'Get-DbaDbFileGrowth',
        'Get-DbaDbFileMapping',
        'Get-DbaDbForeignKey',
        'Get-DbaDbPartitionFunction',
        'Get-DbaDbPartitionScheme',
        'Get-DbaDbQueryStoreOption',
        'Get-DbaDbObjectTrigger',
        'Get-DbaDbOrphanUser',
        'Get-DbaDbRole',
        'Get-DbaDbRoleMember',
        'Get-DbaDbSchema',
        'Get-DbaDbSequence',
        'Get-DbaDbServiceBrokerService',
        'Get-DbaDbSharePoint',
        'Get-DbaDbIdentity',
        'Get-DbaDbSnapshot',
        'Get-DbaDbStoredProcedure',
        'Get-DbaDbSynonym',
        'Get-DbaDbTable',
        'Get-DbaDbTrigger',
        'Get-DbaDbUdf',
        'Get-DbaDbUser',
        'Get-DbaDbUserDefinedTableType',
        'Get-DbaDbView',
        'Get-DbaDependency',
        'Get-DbaExtendedProperty',
        'Get-DbaFile',
        'Get-DbaHelpIndex',
        'Get-DbaRandomizedDataset',
        'Get-DbaRandomizedDatasetTemplate',
        'Get-DbaRandomizedType',
        'Get-DbaRandomizedValue',
        'Get-DbaSchemaChangeHistory',
        'Get-DbaSuspectPage'
    )
    VariablesToExport      = @()
    AliasesToExport        = @()

    PrivateData            = @{
        PSData = @{
            Tags       = @('sqlserver', 'migrations', 'sql', 'dba', 'databases', 'dbatools')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://dbatools.io'
        }
    }
}
