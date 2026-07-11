@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.core.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = '5c6f10e2-4e0d-4bd5-9f2a-4a3f8f1cbb01'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.core: connect, target, query, script, configure - the universal base of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaMaxMemory',
        'Get-DbaTraceFlag',
        'Get-DbaCustomError',
        'Get-DbaDefaultPath',
        'Get-DbaInstanceProperty',
        'Get-DbaStartupParameter',
        'Get-DbaNetworkConfiguration',
        'Get-DbaService',
        'Connect-DbaInstance',
        'Read-DbaBackupHeader',
        'Get-DbaBackupInformation',
        'Format-DbaBackupInformation',
        'Select-DbaBackupInformation',
        'Test-DbaBackupInformation',
        'Invoke-DbaAdvancedRestore',
        'Restore-DbaDatabase',
        'ConvertTo-DbaDataTable',
        'ConvertTo-DbaTimeline',
        'Disconnect-DbaInstance',
        'Export-DbaCsv',
        'Export-DbaScript',
        'Export-DbatoolsConfig',
        'Get-DbaClientAlias',
        'Get-DbaConnectedInstance',
        'Get-DbatoolsChangeLog',
        'Get-DbatoolsConfig',
        'Get-DbatoolsConfigValue',
        'Get-DbatoolsError',
        'Get-DbatoolsLog',
        'Get-DbatoolsPath'
    )
    VariablesToExport      = @()
    # Shortcut aliases for commands owned by this module (BP-604); registered by Set-Alias in
    # the psm1 and exported explicitly here - auto-loading reads this list without execution.
    AliasesToExport        = @('cdi')

    PrivateData            = @{
        PSData = @{
            Tags       = @('sqlserver', 'migrations', 'sql', 'dba', 'databases', 'dbatools')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://dbatools.io'
        }
    }
}
