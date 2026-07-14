@{
    # Satellite module manifest (migration/specs/modules.md section 5.3). The cmdlet dll is
    # built in dbatools.library and staged here at publish/dev-stage time; CmdletsToExport is
    # maintained by the flip tool (Switch-CommandExport.ps1) and stays an explicit name list -
    # PowerShell auto-loading reads the manifest without executing it, so do not wildcard.
    RootModule             = 'dbatools.performance.psm1'
    ModuleVersion          = '2026.7.6'
    GUID                   = 'd592a0a7-29d6-492a-9932-2ccfd9fd8ebd'
    Author                 = 'the dbatools team'
    CompanyName            = 'Dataplat'
    Copyright              = 'Copyright (c) 2026 by dbatools, licensed under MIT'
    Description            = 'dbatools.performance: read-mostly observation commands - part of the dbatools module family'
    PowerShellVersion      = '3.0'

    RequiredModules        = @(
        @{ ModuleName = 'dbatools.library'; ModuleVersion = '2025.12.28' }
    )

    # Satellites never carry .ps1 command functions (specs/contracts.md section 2)
    FunctionsToExport      = @()
    CmdletsToExport        = @(
        'Get-DbaRgResourcePool',
        'Add-DbaPfDataCollectorCounter',
        'Clear-DbaConnectionPool',
        'Clear-DbaLatchStatistics',
        'Clear-DbaPlanCache',
        'Clear-DbaWaitStatistics',
        'Export-DbaExecutionPlan',
        'Export-DbaPfDataCollectorSetTemplate',
        'Find-DbaDbDisabledIndex',
        'Find-DbaDbDuplicateIndex',
        'Find-DbaDbGrowthEvent',
        'Find-DbaDbUnusedIndex',
        'Get-DbaAvailableCollation',
        'Get-DbaBuild',
        'Get-DbaConnection',
        'Get-DbaCpuRingBuffer',
        'Get-DbaCpuUsage',
        'Get-DbaDbccMemoryStatus',
        'Get-DbaDbccProcCache',
        'Get-DbaDbccSessionBuffer',
        'Get-DbaDbDbccOpenTran',
        'Get-DbaDbExtentDiff',
        'Get-DbaDbFeatureUsage',
        'Get-DbaDbLogSpace',
        'Get-DbaDbMemoryUsage',
        'Get-DbaDbPageInfo',
        'Get-DbaDbSpace',
        'Get-DbaDbVirtualLogFile',
        'Get-DbaDeprecatedFeature',
        'Get-DbaDump',
        'Get-DbaErrorLog',
        'Get-DbaEstimatedCompletionTime',
        'Get-DbaExecutionPlan',
        'Get-DbaExternalProcess',
        'Get-DbaIoLatency',
        'Get-DbaLatchStatistic',
        'Get-DbaManagementObject',
        'Get-DbaMemoryCondition',
        'Get-DbaMemoryUsage',
        'Get-DbaModule',
        'Get-DbaNetworkActivity',
        'Get-DbaOleDbProvider',
        'Get-DbaOpenTransaction',
        'Get-DbaPfAvailableCounter',
        'Get-DbaPfDataCollector',
        'Get-DbaPfDataCollectorCounter',
        'Get-DbaPfDataCollectorCounterSample',
        'Get-DbaPfDataCollectorSet',
        'Get-DbaPfDataCollectorSetTemplate',
        'Get-DbaPlanCache',
        'Get-DbaQueryExecutionTime',
        'Get-DbaResourceGovernor',
        'Get-DbaRgClassifierFunction',
        'Get-DbaRgWorkloadGroup',
        'Get-DbaSpinLockStatistic',
        'Get-DbaTempdbUsage',
        'Get-DbaTopResourceUsage',
        'Get-DbaUptime',
        'Get-DbaWaitingTask',
        'Get-DbaWaitResource',
        'Get-DbaWaitStatistic',
        'Get-DbaWindowsLog',
        'Import-DbaPfDataCollectorSetTemplate',
        'Invoke-DbaDiagnosticQuery',
        'Invoke-DbaPfRelog',
        'Measure-DbaDbVirtualLogFile',
        'New-DbaDiagnosticAdsNotebook',
        'New-DbaRgResourcePool',
        'New-DbaRgWorkloadGroup',
        'Remove-DbaPfDataCollectorCounter',
        'Remove-DbaPfDataCollectorSet',
        'Remove-DbaRgResourcePool',
        'Remove-DbaRgWorkloadGroup',
        'Save-DbaDiagnosticQueryScript',
        'Set-DbaResourceGovernor',
        'Set-DbaRgResourcePool',
        'Set-DbaRgWorkloadGroup',
        'Start-DbaPfDataCollectorSet'
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
