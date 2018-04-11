# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"                    = 'autodetect_$script:instance1'
    # run on scenario 2016
    "2016"                      = 'autodetect_$script:instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"                 = 'autodetect_$script:instance2,$script:instance3'
    #run on scenario service_restarts - SQL Server service tests that might disrupt other tests
    "service_restarts"             = @(
        'Start-DbaSqlService',
        'Stop-DbaSqlService',
        'Restart-DbaSqlService',
        'Get-DbaSqlService',
        'Update-DbaSqlServiceAccount',
        'Enable-DbaAgHadr',
        'Disable-DbaAgHadr',
        'Reset-DbaAdmin'
    )
    # do not run on appveyor
    # a bug in SMO prevents availability group scripting :(
    "appveyor_disabled"               = @(
    'Export-DbaAvailabilityGroup'
    )
    # do not run everywhere
    "disabled"                  = @()
}