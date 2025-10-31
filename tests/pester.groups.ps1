# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"            = 'autodetect_$TestConfig.instance1'
    # run on scenario 2016
    "2016"              = 'autodetect_$TestConfig.instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"         = 'autodetect_$TestConfig.instance2,$TestConfig.instance3'
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
        'Backup-DbaDbCertificate',
        'Test-DbaDbLogShipStatus'
    )
    # do not run everywhere
    "disabled"          = @()
}