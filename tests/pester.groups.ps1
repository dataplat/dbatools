# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"            = 'autodetect_$TestConfig.instance1'
    # run on scenario 2016
    "2016"              = 'autodetect_$TestConfig.instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"         = 'autodetect_$TestConfig.instance2,$TestConfig.instance3'
    # do not run on appveyor
    "appveyor_disabled" = @(
        'Backup-DbaDbCertificate',
        'Test-DbaDbLogShipStatus',
        'Invoke-DbaDbMirroring',
        'New-DbaEndpoint',
        # Temporary disabled due to long runtimes
        'Export-DbaDacPackage',
        'Install-DbaSqlPackage',
        'Install-DbaDarlingData'
    )
    # do not run everywhere
    "disabled"          = @()
}