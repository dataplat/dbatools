#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        }

        It "Should get 2 dbatoolsci jobs" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 | Where-Object Name -match "dbatoolsci_testjob"
            $results.Count | Should -Be 2
        }

        It "Should get a specific job" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $results.Name | Should -Be "dbatoolsci_testjob"
        }
    }
    Context "Command gets no disabled jobs" {
        It "Should return only enabled jobs" {
        It "Should return only enabled jobs" {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_disabled -Disabled
            try {
                $results = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -ExcludeDisabledJobs | Where-Object Name -match "dbatoolsci_testjob"
                $results.Enabled -contains $false | Should -Be $false
            } catch {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
            }
        }
    }
    Context "Command doesn't get excluded job" {
        It "Should not return excluded job" {
        It "Should not return excluded job" {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_disabled -Disabled
            try {
                $results = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -ExcludeJob dbatoolsci_testjob | Where-Object Name -match "dbatoolsci_testjob"
                $results.Name -contains "dbatoolsci_testjob" | Should -Be $false
            } catch {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
            }
        }
    }
    Context "Command doesn't get excluded category" {
        It "Should not return excluded job" {
        It "Should not return excluded job" {
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "Cat1"
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "Cat2"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_cat1 -Category "Cat1"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_cat2 -Category "Cat2"
            try {
                $results = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -ExcludeCategory "Cat2" | Where-Object Name -match "dbatoolsci_testjob"
                $results.Name -contains "dbatoolsci_testjob_cat2" | Should -Be $false
            } catch {
                $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "Cat1", "Cat2" -Confirm:$false
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob_cat1, dbatoolsci_testjob_cat2 -Confirm:$false
            }
        }
    }
    Context "Command gets jobs when databases are specified" {
        BeforeAll {
            $jobName1 = "dbatoolsci_dbfilter_$(Get-Random)"
            $jobName2 = "dbatoolsci_dbfilter_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName1 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName1 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName1 -StepName "TSQL-y" -Subsystem TransactSql -Database "tempdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName1 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"

            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName2 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName2 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName2 -StepName "TSQL-y" -Subsystem TransactSql -Database "model"
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName2 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName1, $jobName2 -Confirm:$false
        }

        It "Returns result with single database" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Database tempdb
            $resultSingleDatabase.Count | Should -BeGreaterOrEqual 1
        }

        It "Returns job result for Database: tempdb" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Database tempdb
            $resultSingleDatabase.Name -contains $jobName1 | Should -BeTrue
        }

        It "Returns both jobs with double database" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Database tempdb, model
            $resultMultipleDatabases.Count | Should -BeGreaterOrEqual 2
        }

        It "Includes job result for Database: model" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Database tempdb, model
            $resultMultipleDatabases.Name -contains $jobName2 | Should -BeTrue
        }
    }
}