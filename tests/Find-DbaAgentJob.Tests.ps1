#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "JobName",
                "ExcludeJobName",
                "StepName",
                "LastUsed",
                "IsDisabled",
                "IsFailed",
                "IsNotScheduled",
                "IsNoEmailNotification",
                "Category",
                "Owner",
                "Since",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds jobs using all parameters" {
        BeforeAll {
            #subsystemServer needs the real underlying name, and it doesn't work if targeting something like localhost\namedinstance
            # the typical error would be WARNING: [17:19:26][New-DbaAgentJobStep] Something went wrong creating the job step | The specified '@server' is
            #invalid (valid values are returned by sp_helpserver).
            $srvName = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select @@servername as sn" -as PSObject
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_testjob'
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsregr_testjob' -OwnerLogin 'sa'
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job 'dbatoolsregr_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category 'dbatoolsci_job_category' -CategoryType LocalJob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_testjob_disabled' -Category 'dbatoolsci_job_category' -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_testjob_disabled' -StepId 1 -StepName 'dbatoolsci Test Step' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command 'SELECT * FROM master.sys.all_columns' -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob, dbatoolsregr_testjob, dbatoolsci_testjob_disabled -Confirm:$false
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category 'dbatoolsci_job_category' -Confirm:$false
        }

        It "Should find a specific job" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $results.name | Should -Be "dbatoolsci_testjob"
        }
        It "Should find a specific job but not an excluded job" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job *dbatoolsci* -ExcludeJobName dbatoolsci_testjob_disabled
            $results.name | Should -Not -Be "dbatoolsci_testjob_disabled"
        }
        It "Should find a specific job with a specific step" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -StepName 'dbatoolsci Test Step'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }
        It "Should find jobs not used in the last 10 days" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -LastUsed 10
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should find jobs disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsDisabled
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }
        It "Should find 1 job disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsDisabled
            $results.count | Should -Be 1
        }
        It "Should find jobs that have not been scheduled" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNotScheduled
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should find 2 jobs that have no schedule" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNotScheduled -Job *dbatoolsci*
            $results.count | Should -Be 2
        }
        It "Should find jobs that have no email notification" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNoEmailNotification
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Category 'dbatoolsci_job_category'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }
        It "Should find jobs that are owned by sa" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Owner 'sa'
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should find jobs that have been failed since July of 2016" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsFailed -Since '2016-07-01 10:47:00'
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should work with multiple wildcard passed in (see #9572)" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job *dbatoolsci*, *dbatoolsregr* -ExcludeJobName dbatoolsci_testjob_disabled
            $results.Count | Should -Be 2
        }
    }
}