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
        'Restart-DbaService',
        'Get-DbaService',
        'Update-DbaServiceAccount',
        'Enable-DbaAgHadr',
        'Disable-DbaAgHadr',
        'Reset-DbaAdmin'
    )
    # do not run on appveyor
    "appveyor_disabled" = @(
        # takes too long
        'Install-DbaSqlWatch',
        'Uninstall-DbaSqlWatch',
        # weird too often
        'Add-DbaComputerCertificate',
        'Get-DbaComputerCertificate',
        'Get-DbaMsdtc',
        # a bug in SMO prevents availability group scripting :(
        'Export-DbaAvailabilityGroup',
        # Non-useful info from newly started sql servers
        'Get-DbaCpuRingBuffer',
        'Get-DbaLatchStatistic',
        # these work but fail too often on appveyor
        # will revisit once they get their new data center
        'Remove-DbaAvailabilityGroup',
        'Test-DbaLastBackup',
        'Reset-DbaAdmin',
        'Remove-DbaAgDatabase',
        'New-DbaAvailabilityGroup',
        'Export-DbaDacPackage',
        'Set-DbaAgReplica',
        'Test-DbaOptimizeForAdHoc',
        'Test-DbaDbRecoveryModel',
        'Set-DbaDbState',
        'Test-DbaDeprecatedFeature',
        'Test-DbaServerName',
        'Test-DbaTempDbConfig',
        'Test-DbaDbVirtualLogFile',
        'Test-DbaAgentJobOwner',
        'Resume-DbaAgDbDataMovement',
        'Get-DbaDbMasterKey',
        'Test-DbaJobOwner'
    )
    # do not run everywhere
    "disabled"          = @()
}