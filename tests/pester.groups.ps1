# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario 2008R2
    "2008R2"                    = 'autodetect_$script:instance1'
    # run on scenario 2016
    "2016"                      = 'autodetect_$script:instance2'
    # run on scenario 2016_2017 - tests that need developer license
    "2016_2017"                 = @(
        'Copy-DbaCredential',
        'Copy-DbaAgentJob',
        'Copy-DbaLinkedServer',
        'Copy-DbaAgentAlert',
        'Copy-DbaAgentCategory',
        'Copy-DbaAgentOperator',
        'Copy-DbaDatabase',
        'Dismount-DbaDatabase',
        'Copy-DbaDatabaseAssembly',
        'Copy-DbaCustomError'
    )
    #run on scenario 2016_service - SQL Server service tests that might disrupt other tests
    "2016_service"              = @(
        'Start-DbaSqlService',
        'Stop-DbaSqlService',
        'Restart-DbaSqlService',
        'Get-DbaSqlService',
        'Update-DbaSqlServiceAccount'
    )
    # do not run on appveyor
    "appveyor_disabled"         = @(
        'Dismount-DbaDatabase'
    )
    
    # do not run everywhere
    "disabled"                  = @()
}