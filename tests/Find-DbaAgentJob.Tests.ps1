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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have JobName as a parameter" {
            $CommandUnderTest | Should -HaveParameter JobName -Type String[]
        }
        It "Should have ExcludeJobName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJobName -Type String[]
        }
        It "Should have StepName as a parameter" {
            $CommandUnderTest | Should -HaveParameter StepName -Type String[]
        }
        It "Should have LastUsed as a parameter" {
            $CommandUnderTest | Should -HaveParameter LastUsed -Type Int32
        }
        It "Should have IsDisabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsDisabled -Type Switch
        }
        It "Should have IsFailed as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsFailed -Type Switch
        }
        It "Should have IsNotScheduled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsNotScheduled -Type Switch
        }
        It "Should have IsNoEmailNotification as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsNoEmailNotification -Type Switch
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[]
        }
        It "Should have Owner as a parameter" {
            $CommandUnderTest | Should -HaveParameter Owner -Type String
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Find-DbaAgentJob Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $srvName = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select @@servername as sn" -as PSObject
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        $null = Start-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob'
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
        $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category' -CategoryType LocalJob
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob_disabled' -Category 'dbatoolsci_job_category' -Disabled
        $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob_disabled' -StepId 1 -StepName 'dbatoolsci Test Step' -Subsystem TransactSql -SubsystemServer $srvName.sn -Command 'SELECT * FROM master.sys.all_columns' -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -RetryAttempts 1 -RetryInterval 2
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category' -Confirm:$false
    }

    Context "Command finds jobs using all parameters" {
        It "Should find a specific job" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
            $results.name | Should -Be "dbatoolsci_testjob"
        }

        It "Should find a specific job but not an excluded job" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Job *dbatoolsci* -ExcludeJobName dbatoolsci_testjob_disabled
            $results.name | Should -Not -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find a specific job with a specific step" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -StepName 'dbatoolsci Test Step'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs not used in the last 10 days" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -LastUsed 10
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsDisabled
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find 1 job disabled from running" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsDisabled
            $results.count | Should -Be 1
        }

        It "Should find jobs that have not been scheduled" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsNotScheduled
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find 2 jobs that have no schedule" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsNotScheduled -Job *dbatoolsci*
            $results.count | Should -Be 2
        }

        It "Should find jobs that have no email notification" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsNoEmailNotification
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category'
            $results.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs that are owned by sa" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Owner 'sa'
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have been failed since July of 2016" {
            $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsFailed -Since '2016-07-01 10:47:00'
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
