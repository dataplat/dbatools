#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJob",
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
                "Job",
                "ExcludeJob",
                "Database",
                "Category",
                "ExcludeDisabledJobs",
                "EnableException",
                "ExcludeCategory",
                "IncludeExecution",
                "Type"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }

        It "Should get 2 dbatoolsci jobs" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match "dbatoolsci_testjob"
            $results.Count | Should -Be 2
        }

        It "Should get a specific job" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be "dbatoolsci_testjob"
        }
    }
    Context "Command gets no disabled jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }

        It "Should return only enabled jobs" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -ExcludeDisabledJobs | Where-Object Name -match "dbatoolsci_testjob"
            $results.Enabled -contains $false | Should -Be $false
        }
    }
    Context "Command doesn't get excluded job" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }

        It "Should not return excluded job" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -ExcludeJob dbatoolsci_testjob | Where-Object Name -match "dbatoolsci_testjob"
            $results.Name -contains "dbatoolsci_testjob" | Should -Be $false
        }
    }
    Context "Command doesn't get excluded category" {
        BeforeAll {
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "Cat1"
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "Cat2"

            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_cat1 -Category "Cat1"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_cat2 -Category "Cat2"
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "Cat1", "Cat2"

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_cat1, dbatoolsci_testjob_cat2
        }

        It "Should not return excluded job" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -ExcludeCategory "Cat2" | Where-Object Name -match "dbatoolsci_testjob"
            $results.Name -contains "dbatoolsci_testjob_cat2" | Should -Be $false
        }
    }
    Context "Command gets jobs when databases are specified" {
        BeforeAll {
            $jobName1 = "dbatoolsci_dbfilter_$(Get-Random)"
            $jobName2 = "dbatoolsci_dbfilter_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName1 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName1 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName1 -StepName "TSQL-y" -Subsystem TransactSql -Database "tempdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName1 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"

            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName2 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName2 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName2 -StepName "TSQL-y" -Subsystem TransactSql -Database "model"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName2 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName1, $jobName2
        }

        It "Returns result with single database" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $resultSingleDatabase.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns job result for Database: tempdb" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $resultSingleDatabase.Name -contains $jobName1 | Should -BeTrue
        }

        It "Returns both jobs with double database" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Database tempdb, model
            $resultMultipleDatabases.Count | Should -BeGreaterOrEqual 2
        }

        It "Includes job result for Database: model" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Database tempdb, model
            $resultMultipleDatabases.Name -contains $jobName2 | Should -BeTrue
        }
    }
    Context "Command validates null/empty Job parameter" {
        It "Should return no jobs when -Job is null" {
            $nullVariable = $null
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $nullVariable
            $results | Should -BeNullOrEmpty
        }

        It "Should return no jobs when -Job is empty string" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job ""
            $results | Should -BeNullOrEmpty
        }

        It "Should return no jobs when -Job is whitespace" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "   "
            $results | Should -BeNullOrEmpty
        }

        It "Should ignore -ExcludeJob when it contains null values" {
            $nullVariable = $null
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -ExcludeJob $nullVariable
            $results | Should -Not -BeNullOrEmpty
        }
    }
    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Category",
                "OwnerLoginName",
                "CurrentRunStatus",
                "CurrentRunRetryAttempt",
                "Enabled",
                "LastRunDate",
                "LastRunOutcome",
                "HasSchedule",
                "OperatorToEmail",
                "CreateDate"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Job"
        }
    }
}