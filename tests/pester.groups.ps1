# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"            = 'autodetect_$TestConfig.instance1'
    # run on scenario 2016
    "2016"              = 'autodetect_$TestConfig.instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"         = 'autodetect_$TestConfig.instance2,$TestConfig.instance3'
    # run on scenario SINGLE - tests that need just a single instance
    "SINGLE"            = 'autodetect_$TestConfig.InstanceSingle'
    # run on scenario MULTI - tests that need multiple instances
    "MULTI"             = 'autodetect_$TestConfig.InstanceMulti'
    # run on scenario COPY - tests that need to copy between instances
    "COPY"              = 'autodetect_$TestConfig.InstanceCopy'
    # run on scenario HADR - tests that need AGs, mirroring, logshipping
    "HADR"              = 'autodetect_$TestConfig.InstanceHadr'
    # run on scenario RESTART - tests that need to restart the sql instance
    "RESTART"           = 'autodetect_$TestConfig.InstanceRestart'
    # do not run on appveyor
    "appveyor_disabled" = @(
        'Backup-DbaDbCertificate',
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