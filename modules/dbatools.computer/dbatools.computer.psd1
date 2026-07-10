@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.computer.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = 'f9b7f062-95dc-4f5c-bc8f-b9976051dad1'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.computer: the Windows around the SQL Server - part of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaPowerPlan',
        'Get-DbaOperatingSystem',
        'Get-DbaDiskSpace',
        'Get-DbaPageFileSetting',
        'Get-DbaComputerSystem',
        'Get-DbaClientProtocol',
        'Get-DbaLocaleSetting',
        'Get-DbaForceNetworkEncryption',
        'Get-DbaMsdtc',
        'Get-DbaPrivilege',
        'Get-DbaProductKey',
        'Get-DbaFeature',
        'Get-DbaComputerCertificate',
        'Test-DbaComputerCertificateExpiration',
        'Get-DbaNetworkEncryption',
        'Test-DbaPowerPlan',
        'Test-DbaSpn',
        'Get-DbaRegistryRoot',
        'Get-DbaInstalledPatch',
        'Set-DbaPowerPlan',
        'Backup-DbaComputerCertificate',
        'Remove-DbaComputerCertificate',
        'Add-DbaComputerCertificate',
        'Enable-DbaForceNetworkEncryption',
        'Disable-DbaForceNetworkEncryption',
        'New-DbaComputerCertificateSigningRequest',
        'New-DbaComputerCertificate',
        'Get-DbaNetworkCertificate',
        'Get-DbaSpn',
        'Get-DbaFirewallRule',
        'Test-DbaNetworkCertificate',
        'Remove-DbaNetworkCertificate',
        'New-DbaFirewallRule',
        'Set-DbaPrivilege',
        'Set-DbaSpn',
        'Remove-DbaSpn',
        'Remove-DbaFirewallRule'
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
