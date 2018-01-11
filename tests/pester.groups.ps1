# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"            = 'autodetect_$script:instance1'
    # run on scenario 2016
    "2016"              = 'autodetect_$script:instance2'
    #run on scenario 2016_service - SQL Server service tests that might disrupt other tests
    "2016_service"      = @(
        'Start-DbaSqlService',
        'Stop-DbaSqlService',
        'Restart-DbaSqlService',
        'Get-DbaSqlService',
        'Update-DbaSqlServiceAccount'
    )
    # do not run on appveyor
    "appveyor_disabled" = @(
        'Get-DbaDatabaseState',
        'Dismount-DbaDatabase'
    )

    # do not run everywhere
    "disabled"          = @()
}