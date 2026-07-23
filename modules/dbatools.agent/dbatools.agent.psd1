@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.agent.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = '21467488-ae38-4806-8e36-211263787551'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.agent: SQL Agent and Database Mail - the notification stack of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaAgentJob',
        'Get-DbaDbMailProfile',
        'Copy-DbaAgentAlert',
        'Copy-DbaAgentJob',
        'Copy-DbaAgentJobCategory',
        'Copy-DbaAgentJobStep',
        'Copy-DbaAgentOperator',
        'Copy-DbaAgentProxy',
        'Copy-DbaAgentSchedule',
        'Copy-DbaAgentServer',
        'Find-DbaAgentJob',
        'Get-DbaAgentAlert',
        'Get-DbaAgentAlertCategory',
        'Get-DbaAgentJobCategory',
        'Get-DbaAgentJobHistory',
        'Get-DbaAgentJobOutputFile',
        'Get-DbaAgentJobStep',
        'Get-DbaAgentLog',
        'Get-DbaAgentOperator',
        'Get-DbaAgentProxy',
        'Get-DbaAgentSchedule',
        'Get-DbaAgentServer',
        'Get-DbaDbMail',
        'Get-DbaDbMailAccount',
        'Get-DbaDbMailConfig',
        'Get-DbaDbMailHistory',
        'Get-DbaDbMailLog',
        'Get-DbaDbMailServer',
        'Install-DbaAgentAdminAlert',
        'New-DbaAgentAlert',
        'New-DbaAgentAlertCategory',
        'New-DbaAgentJob',
        'New-DbaAgentJobCategory',
        'New-DbaAgentJobStep',
        'Get-DbaRunningJob',
        'Remove-DbaAgentAlert',
        'Remove-DbaAgentAlertCategory',
        'Remove-DbaAgentJobCategory',
        'Remove-DbaAgentOperator',
        'Remove-DbaAgentProxy',
        'Remove-DbaAgentSchedule',
        'Remove-DbaDbMailAccount',
        'Remove-DbaDbMailProfile',
        'Set-DbaAgentJobOwner',
        'Stop-DbaAgentJob',
        'New-DbaAgentOperator',
        'New-DbaAgentProxy'
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
