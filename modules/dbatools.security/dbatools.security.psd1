@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.security.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = 'b08b730c-6849-4aeb-8987-e9281f21d86e'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.security: logins, roles, certificates, encryption and audit commands of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaDbCertificate',
        'Add-DbaServerRoleMember',
        'Copy-DbaDbCertificate',
        'Backup-DbaDbCertificate',
        'Backup-DbaDbMasterKey',
        'Backup-DbaServiceMasterKey',
        'Compare-DbaLogin',
        'Disable-DbaDbEncryption',
        'Enable-DbaDbEncryption',
        'Export-DbaLogin',
        'Export-DbaServerRole',
        'Export-DbaSysDbUserObject',
        'Get-DbaDbAsymmetricKey',
        'Get-DbaDbEncryptionKey',
        'Get-DbaDbMasterKey',
        'Get-DbaPbmCategory',
        'Find-DbaLoginInGroup',
        'Get-DbaPbmPolicy',
        'Get-DbaPbmObjectSet',
        'New-DbaServiceMasterKey',
        'Export-DbaUser',
        'Remove-DbaDbAsymmetricKey',
        'Remove-DbaDbCertificate',
        'Remove-DbaDbEncryptionKey',
        'Remove-DbaDbMasterKey',
        'Remove-DbaLogin',
        'Remove-DbaServerRole',
        'Remove-DbaServerRoleMember',
        'Set-DbaServerRole',
        'Set-DbaDbMasterKey',
        'Rename-DbaLogin',
        'Stop-DbaDbEncryption',
        'Sync-DbaLoginPassword',
        'Sync-DbaLoginPermission',
        'Test-DbaLoginPassword',
        'Reset-DbaAdmin',
        'Set-DbaLogin',
        'Restore-DbaDbCertificate',
        'Start-DbaDbEncryption',
        'Test-DbaWindowsLogin',
        'Get-DbaInstanceAudit',
        'Get-DbaInstanceAuditSpecification',
        'New-DbaInstanceAuditSpecification',
        'Get-DbaLogin',
        'Get-DbaPbmCategorySubscription',
        'Get-DbaPbmStore',
        'Get-DbaPbmCondition',
        'New-DbaDbAsymmetricKey',
        'New-DbaDbCertificate',
        'New-DbaLogin',
        'New-DbaInstanceAudit',
        'Set-DbaInstanceAudit'
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
