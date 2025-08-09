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
        # tests that work locally against SQL Server 2022 instances without problems but fail on AppVeyor
        'ConvertTo-DbaXESession',
        'Export-DbaUser',
        'Get-DbaPermission',
        'Get-DbaUserPermission',
        'Install-DbaDarlingData',
        'Invoke-DbaWhoisActive',
        'Remove-DbaAvailabilityGroup',
        'Remove-DbaDatabaseSafely',
        'Sync-DbaLoginPermission',
        'Dismount-DbaDatabase',
        # tests that fail locally against SQL Server 2022 instances and fail on AppVeyor
        'Set-DbaAgentJobStep',   # This outputs the message "[New-DbaAgentJob] Something went wrong creating the job. | Value cannot be null. / Parameter name: newParent" and failes in Describe with "Cannot bind argument to parameter 'SqlInstance' because it is null."
        'Watch-DbaDbLogin',
        # tests that fail because the command does not work
        'Copy-DbaDbCertificate',
        'Export-DbaDacPackage',
        # takes too long
        'Install-DbaSqlWatch',
        'Uninstall-DbaSqlWatch',
        'Get-DbaExecutionPlan',
        # Non-useful info from newly started sql servers
        'Get-DbaCpuRingBuffer',
        'Get-DbaLatchStatistic',
        # uses a backup that only works on SQL Server 2022
        'Get-DbaEstimatedCompletionTime',
        # fix shortly, broke once we moved to Get-TestConfig
        'Remove-DbaLinkedServer'
    )
    # do not run everywhere
    "disabled"          = @()
}

