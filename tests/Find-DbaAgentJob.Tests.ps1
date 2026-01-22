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
            $srvName = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "select @@servername as sn" -As SingleValue
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 0
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsci_testjob'
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsregr_testjob' -OwnerLogin 'sa'
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsregr_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category 'dbatoolsci_job_category' -CategoryType LocalJob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsci_testjob_disabled' -Category 'dbatoolsci_job_category' -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job 'dbatoolsci_testjob_disabled' -StepId 1 -StepName 'dbatoolsci Test Step' -Subsystem TransactSql -SubsystemServer $srvName -Command 'SELECT * FROM master.sys.all_columns' -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob, dbatoolsregr_testjob, dbatoolsci_testjob_disabled
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category 'dbatoolsci_job_category'
        }

        It "Should find a specific job" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob
            $results.name | Should -Be "dbatoolsci_testjob"
        }

        It "Should find a specific job but not an excluded job" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job *dbatoolsci* -ExcludeJobName dbatoolsci_testjob_disabled
            $results.name | Should -Not -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find a specific job with a specific step" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -StepName 'dbatoolsci Test Step'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs not used in the last 10 days" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -LastUsed 10
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find 1 job disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -IsDisabled
            $results | Should -HaveCount 1
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs that have not been scheduled" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -IsNotScheduled
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find 2 jobs that have no schedule" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -IsNotScheduled -Job *dbatoolsci*
            $results | Should -HaveCount 2
        }

        It "Should find jobs that have no email notification" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -IsNoEmailNotification
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Category 'dbatoolsci_job_category'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs that are owned by sa" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Owner 'sa'
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have been failed since July of 2016" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -IsFailed -Since '2016-07-01 10:47:00'
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should work with multiple wildcard passed in (see #9572)" {
            $results = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job *dbatoolsci*, *dbatoolsregr* -ExcludeJobName dbatoolsci_testjob_disabled
            $results | Should -HaveCount 2
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Category',
                'OwnerLoginName',
                'CurrentRunStatus',
                'CurrentRunRetryAttempt',
                'Enabled',
                'LastRunDate',
                'LastRunOutcome',
                'DateCreated',
                'HasSchedule',
                'OperatorToEmail',
                'CreateDate'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Includes dbatools-added properties" {
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'InstanceName'
            $result.PSObject.Properties.Name | Should -Contain 'SqlInstance'
            $result.PSObject.Properties.Name | Should -Contain 'JobName'
        }
    }
}