# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
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
    # run on scenario Legacy1 - tests that use instance1 and will be changed to InstanceSingle in the next iteration
    "Legacy1"           = 'autodetect_$TestConfig.instance1'
    # do not run on appveyor
    "appveyor_disabled" = @(
        'Backup-DbaDbCertificate',
        'Get-DbaInstalledPatch',  # disabled because SQL Server 2019 instance does not have any patches installed
        'Invoke-DbaDbMirroring',
        'New-DbaEndpoint',
        'Restore-DbaDatabase',  # disabled due to failures in appveyor environment which will be analyzed later
        # Temporary disabled due to long runtimes
        'Export-DbaDacPackage',
        'Install-DbaSqlPackage',
        'Install-DbaDarlingData'
    )
    # do not run everywhere
    "disabled"          = @()
}