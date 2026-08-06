@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.migration.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = 'd5682377-4abf-47d8-b0c7-20eb2cb64397'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.migration: instance-to-instance estate migration, the Copy-Dba* family and Start-DbaMigration - part of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    # The psm1 hard-fails when no edition dll is staged, so this list and the root
    # dbatools.psd1 RequiredModules entry move together: emptying this one without also
    # dropping that entry breaks every Import-Module dbatools.
    CmdletsToExport        = @(
        'Copy-DbaBackupDevice',
        'Copy-DbaCredential',
        'Copy-DbaCustomError',
        'Copy-DbaDatabase',
        'Copy-DbaDataCollector',
        'Copy-DbaDbAssembly',
        'Copy-DbaDbMail',
        'Copy-DbaDbQueryStoreOption',
        'Copy-DbaDbTableData',
        'Copy-DbaDbViewData',
        'Copy-DbaEndpoint',
        'Copy-DbaExtendedStoredProcedure',
        'Copy-DbaInstanceAudit',
        'Copy-DbaInstanceAuditSpecification',
        'Copy-DbaInstanceTrigger',
        'Copy-DbaLinkedServer',
        'Copy-DbaLogin',
        'Copy-DbaPolicyManagement',
        'Copy-DbaResourceGovernor',
        'Copy-DbaServerRole',
        'Copy-DbaSpConfigure',
        'Copy-DbaStartupProcedure',
        'Copy-DbaSystemDbUserObject'
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
