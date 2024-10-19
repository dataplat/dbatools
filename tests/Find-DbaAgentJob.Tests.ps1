param($ModuleName = 'dbatools')

Describe "Find-DbaAgentJob Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaAgentJob
        }
        It "has all the required parameters" {
            $requiredParameters = @(
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
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Find-DbaAgentJob Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $srvName = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "select @@servername as sn" -as PSObject
        $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        $null = Start-DbaAgentJob -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob'
        $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci_job_category' -CategoryType LocalJob
        $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob_disabled' -Category 'dbatoolsci_job_category' -Disabled
        $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job 'dbatoolsci_testjob_disabled' -StepId 1 -StepName 'dbatoolsci Test Step' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command 'SELECT * FROM master.sys.all_columns' -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        $null = Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci_job_category' -Confirm:$false
    }

    Context "Command finds jobs using all parameters" {
        It "Should find a specific job" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob
            $results.name | Should -Be "dbatoolsci_testjob"
        }

        It "Should find a specific job but not an excluded job" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -Job *dbatoolsci* -ExcludeJobName dbatoolsci_testjob_disabled
            $results.name | Should -Not -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find a specific job with a specific step" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -StepName 'dbatoolsci Test Step'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs not used in the last 10 days" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -LastUsed 10
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsDisabled
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find 1 job disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsDisabled
            $results.count | Should -Be 1
        }

        It "Should find jobs that have not been scheduled" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsNotScheduled
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find 2 jobs that have no schedule" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsNotScheduled -Job *dbatoolsci*
            $results.count | Should -Be 2
        }

        It "Should find jobs that have no email notification" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsNoEmailNotification
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -Category 'dbatoolsci_job_category'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs that are owned by sa" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -Owner 'sa'
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have been failed since July of 2016" {
            $results = Find-DbaAgentJob -SqlInstance $global:instance2 -IsFailed -Since '2016-07-01 10:47:00'
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
