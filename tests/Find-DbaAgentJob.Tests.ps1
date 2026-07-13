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
                "Pattern",
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

    Context "Wildcard filtering" {
        InModuleScope dbatools {
            BeforeAll {
                $script:agentJobs = @(
                    [PSCustomObject]@{ Name = "Backup1Nightly"; JobSteps = @([PSCustomObject]@{ Name = "LoadData" }) }
                    [PSCustomObject]@{ Name = "Backup2Nightly"; JobSteps = @([PSCustomObject]@{ Name = "LoadMeta" }) }
                    [PSCustomObject]@{ Name = "ETL1"; JobSteps = @([PSCustomObject]@{ Name = "Extract" }) }
                    [PSCustomObject]@{ Name = "ETL2"; JobSteps = @([PSCustomObject]@{ Name = "LoadData" }) }
                    [PSCustomObject]@{ Name = "Literal*Job"; JobSteps = @([PSCustomObject]@{ Name = "Literal*Step" }) }
                    [PSCustomObject]@{ Name = "LiteralXJob"; JobSteps = @([PSCustomObject]@{ Name = "LiteralXStep" }) }
                )
                $script:agentServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    JobServer          = [PSCustomObject]@{ Jobs = $script:agentJobs }
                }
                Mock Connect-DbaInstance { $script:agentServer }
            }

            It "supports question-mark and character-class job wildcards" {
                (Get-JobList -SqlInstance "sql1" -JobFilter "Backup?Nightly").Name | Should -Be @("Backup1Nightly", "Backup2Nightly")
                (Get-JobList -SqlInstance "sql1" -JobFilter "ETL[12]").Name | Should -Be @("ETL1", "ETL2")
            }

            It "supports escaped literal asterisks and step wildcards" {
                $escapedJobName = [System.Management.Automation.WildcardPattern]::Escape("Literal*Job")

                (Get-JobList -SqlInstance "sql1" -JobFilter $escapedJobName).Name | Should -Be "Literal*Job"
                (Get-JobList -SqlInstance "sql1" -StepFilter "Load?ata").Name | Should -Be @("Backup1Nightly", "ETL2")
            }
        }
    }

    Context "Public name filters" {
        InModuleScope dbatools {
            BeforeEach {
                $script:publicAgentJobs = foreach ($publicAgentJobName in "Backup1Nightly", "Backup2Nightly", "ETL1", "ETL2", "Literal*Job", "LiteralXJob") {
                    $publicAgentJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job
                    $publicAgentJob.Name = $publicAgentJobName
                    $publicAgentJob
                }
                $script:publicAgentServer = [DbaInstanceParameter]"sql1"
                $script:publicAgentServer | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "sql1"
                $script:publicAgentServer | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
                $script:publicAgentServer | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "sql1"

                Mock Connect-DbaInstance { $script:publicAgentServer }
                Mock Get-JobList { $script:publicAgentJobs }
                Mock Select-DefaultView { $InputObject }
            }

            It "marks JobName and StepName as wildcard-capable" {
                $command = Get-Command Find-DbaAgentJob

                @($command.Parameters["JobName"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.SupportsWildcardsAttribute] }) | Should -HaveCount 1
                @($command.Parameters["StepName"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.SupportsWildcardsAttribute] }) | Should -HaveCount 1
            }

            It "matches job names with regex Pattern OR semantics" {
                $results = Find-DbaAgentJob -SqlInstance "sql1" -Pattern "^Backup\dNightly$", "^ETL2$"

                $results.Name | Should -Be @("Backup1Nightly", "Backup2Nightly", "ETL2")
            }

            It "narrows JobName results by Pattern and keeps ExcludeJobName exact" {
                Mock Get-JobList { $script:publicAgentJobs | Where-Object Name -Like "Literal*" }

                $results = Find-DbaAgentJob -SqlInstance "sql1" -JobName "Literal*" -Pattern "^Literal.*Job$" -ExcludeJobName "Literal*Job"

                $results.Name | Should -Be "LiteralXJob"
            }
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
}
