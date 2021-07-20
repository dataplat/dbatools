# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"            = 'autodetect_$script:instance1'
    # run on scenario 2016
    "2016"              = 'autodetect_$script:instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"         = 'autodetect_$script:instance2,$script:instance3'
    #run on scenario service_restarts - SQL Server service tests that might disrupt other tests
    "service_restarts"  = @(
        'Start-DbaService',
        'Stop-DbaService',
        'Set-DbaStartupParameter',
        'Restart-DbaService',
        'Get-DbaService',
        'Update-DbaServiceAccount',
        'Enable-DbaAgHadr',
        'Disable-DbaAgHadr',
        'Reset-DbaAdmin',
        'Set-DbaTcpPort'
    )
    # do not run on appveyor
    "appveyor_disabled" = @(
        # takes too long
        'Install-DbaSqlWatch',
        'Uninstall-DbaSqlWatch',
        'Get-DbaExecutionPlan',
        # Non-useful info from newly started sql servers
        'Get-DbaCpuRingBuffer',
        'Get-DbaLatchStatistic',
        # times out
        'Copy-DbaResourceGovernor',
        # fails on newer version of SMO
        'Get-DbaUserPermission',
        'Invoke-DbaBalanceDataFiles',
        'Invoke-DbaWhoisActive',
        'Install-DbaDarlingData',
        # previous tests that were failing on older versions too
        'Remove-DbaAvailabilityGroup',
        'Set-DbaAgReplica',
        'Read-DbaAuditFile',
        'Sync-DbaLoginPermission',
        'Read-DbaXEFile',
        'Stop-DbaXESession',
        'Test-DbaTempDbConfig',
        'New-DbaDbUser',
        'Stop-DbaXESession',
        'New-DbaLogin',
        'Watch-DbaDbLogin',
        'ConvertTo-DbaXESession',
        'Test-DbaInstanceName',
        'Test-DbaDeprecatedFeature',
        'Remove-DbaDatabaseSafely',
        'Get-DbaDbMasterKey',
        'Get-DbaPermission',
        'Test-DbaManagementObject',
        'Export-DbaDacPackage',
        'New-DbaDbTransfer',
        'Remove-DbaAgDatabase',
        'New-DbaDbTable',
        'Get-DbaDbSynonym',
        'Get-DbaDbVirtualLogFile'
    )
    # do not run everywhere
    "disabled"          = @()
}
