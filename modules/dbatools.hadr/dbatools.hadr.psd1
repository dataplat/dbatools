@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.hadr.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = '60d9753a-6d10-4c81-8f9c-c8d0e5a0ee1e'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.hadr: high availability and disaster recovery commands of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaAvailabilityGroup',
        'Get-DbaWsfcCluster',
        'Get-DbaWsfcNode',
        'Get-DbaWsfcAvailableDisk',
        'Get-DbaWsfcDisk',
        'Get-DbaWsfcNetwork',
        'Get-DbaWsfcNetworkInterface',
        'Get-DbaWsfcResource',
        'Get-DbaWsfcResourceGroup',
        'Get-DbaWsfcResourceType',
        'Get-DbaWsfcRole',
        'Get-DbaWsfcSharedVolume',
        'Compare-DbaAgReplicaAgentJob',
        'Compare-DbaAgReplicaCredential',
        'Get-DbaAgListener',
        'Get-DbaAgReplica',
        'Get-DbaAgRingBuffer',
        'Get-DbaDbLogShipError',
        'Get-DbaDbMirror',
        'Get-DbaDbMirrorMonitor',
        'Get-DbaEndpoint',
        'Invoke-DbaAgFailover',
        'Grant-DbaAgPermission',
        'Invoke-DbaDbLogShipping',
        'Add-DbaAgDatabase',
        'Add-DbaAgListener',
        'Add-DbaAgReplica',
        'Add-DbaDbMirrorMonitor',
        'Compare-DbaAgReplicaLogin',
        'Compare-DbaAgReplicaOperator',
        'Compare-DbaAgReplicaSync',
        'Compare-DbaAvailabilityGroup',
        'Disable-DbaAgHadr',
        'Enable-DbaAgHadr',
        'Get-DbaAgBackupHistory',
        'Get-DbaAgDatabase',
        'Get-DbaAgDatabaseReplicaState',
        'Get-DbaAgHadr',
        'Invoke-DbaDbLogShipRecovery',
        'Invoke-DbaDbMirrorFailover',
        'Invoke-DbaDbMirroring',
        'Join-DbaAvailabilityGroup'
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
