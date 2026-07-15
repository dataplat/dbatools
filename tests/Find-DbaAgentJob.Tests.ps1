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

        It "marks JobName and StepName as wildcard-capable" {
            $command = Get-Command Find-DbaAgentJob

            @($command.Parameters["JobName"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.SupportsWildcardsAttribute] }) | Should -HaveCount 1
            @($command.Parameters["StepName"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.SupportsWildcardsAttribute] }) | Should -HaveCount 1
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds jobs using all parameters" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob, dbatoolsregr_testjob, dbatoolsci_testjob_disabled
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category 'dbatoolsci_job_category'

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            $results.Name | Should -Contain "dbatoolsci_testjob"
            $results.Name | Should -Contain "dbatoolsregr_testjob"
            $results.Name | Should -Not -Contain "dbatoolsci_testjob_disabled"
        }

    }

    Context "Wildcard and Pattern filtering against real jobs" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $srvName = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "select @@servername as sn" -As SingleValue
            $wildcardJobDefinitions = @(
                [PSCustomObject]@{ Name = "dbatoolsci_Backup1Nightly"; StepName = "dbatoolsci_LoadData" }
                [PSCustomObject]@{ Name = "dbatoolsci_Backup2Nightly"; StepName = "dbatoolsci_LoadMeta" }
                [PSCustomObject]@{ Name = "dbatoolsci_ETL1"; StepName = "dbatoolsci_Extract" }
                [PSCustomObject]@{ Name = "dbatoolsci_ETL2"; StepName = "dbatoolsci_LoadData" }
                [PSCustomObject]@{ Name = "dbatoolsci_Literal*Job"; StepName = "dbatoolsci_Literal*Step" }
                [PSCustomObject]@{ Name = "dbatoolsci_LiteralXJob"; StepName = "dbatoolsci_LiteralXStep" }
            )
            foreach ($wildcardJobDefinition in $wildcardJobDefinitions) {
                $splatAgentJob = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Job         = $wildcardJobDefinition.Name
                    OwnerLogin  = "sa"
                }
                $null = New-DbaAgentJob @splatAgentJob
                $splatJobStep = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Job             = $wildcardJobDefinition.Name
                    StepId          = 1
                    StepName        = $wildcardJobDefinition.StepName
                    Subsystem       = "TransactSql"
                    SubsystemServer = $srvName
                    Command         = "SELECT 1"
                    Database        = "master"
                    OnSuccessAction = "QuitWithSuccess"
                    OnFailAction    = "QuitWithFailure"
                }
                $null = New-DbaAgentJobStep @splatJobStep
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $wildcardJobDefinitions.Name

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "supports question-mark and character-class job wildcards" {
            (Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -JobName "dbatoolsci_Backup?Nightly").Name | Sort-Object | Should -Be @("dbatoolsci_Backup1Nightly", "dbatoolsci_Backup2Nightly")
            (Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -JobName "dbatoolsci_ETL[12]").Name | Sort-Object | Should -Be @("dbatoolsci_ETL1", "dbatoolsci_ETL2")
        }

        It "supports escaped literal asterisks and step wildcards" {
            $escapedJobName = [System.Management.Automation.WildcardPattern]::Escape("dbatoolsci_Literal*Job")
            $splatFindStepWildcard = @{
                SqlInstance = $TestConfig.InstanceSingle
                JobName     = "dbatoolsci_Backup*", "dbatoolsci_ETL*"
                StepName    = "dbatoolsci_Load?ata"
            }

            (Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -JobName $escapedJobName).Name | Should -Be "dbatoolsci_Literal*Job"
            (Find-DbaAgentJob @splatFindStepWildcard).Name | Sort-Object | Should -Be @("dbatoolsci_Backup1Nightly", "dbatoolsci_ETL2")
        }

        It "combines Pattern OR semantics with an exact exclusion" {
            $splatFindPattern = @{
                SqlInstance = $TestConfig.InstanceSingle
                JobName     = "dbatoolsci_Backup*", "dbatoolsci_ETL*"
                Pattern     = "^dbatoolsci_Backup\dNightly$", "^dbatoolsci_ETL2$"
            }
            $splatFindLiteral = @{
                SqlInstance    = $TestConfig.InstanceSingle
                JobName        = "dbatoolsci_Literal*"
                Pattern        = "^dbatoolsci_Literal.*Job$"
                ExcludeJobName = "dbatoolsci_Literal*Job"
            }
            $patternResults = Find-DbaAgentJob @splatFindPattern
            $literalResults = Find-DbaAgentJob @splatFindLiteral

            $patternResults.Name | Sort-Object | Should -Be @("dbatoolsci_Backup1Nightly", "dbatoolsci_Backup2Nightly", "dbatoolsci_ETL2")
            $literalResults.Name | Should -Be "dbatoolsci_LiteralXJob"
        }
    }
}
