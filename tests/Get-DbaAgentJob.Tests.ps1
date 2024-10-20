param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJob Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJob
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "ExcludeJob",
                "Database",
                "Category",
                "ExcludeCategory",
                "ExcludeDisabledJobs",
                "IncludeExecution",
                "Type",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Get-DbaAgentJob Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command gets jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        }
        It "Should get 2 dbatoolsci jobs" {
            $results = Get-DbaAgentJob -SqlInstance $global:instance2 | Where-Object { $_.Name -match "dbatoolsci_testjob" }
            $results.count | Should -Be 2
        }
        It "Should get a specific job" {
            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob
            $results.name | Should -Be "dbatoolsci_testjob"
        }
    }

    Context "Command gets no disabled jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        }
        It "Should return only enabled jobs" {
            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -ExcludeDisabledJobs | Where-Object { $_.Name -match "dbatoolsci_testjob" }
            $results.enabled -contains $False | Should -Be $False
        }
    }

    Context "Command doesn't get excluded job" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled -Confirm:$false
        }
        It "Should not return excluded job" {
            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -ExcludeJob dbatoolsci_testjob | Where-Object { $_.Name -match "dbatoolsci_testjob" }
            $results.name -contains "dbatoolsci_testjob" | Should -Be $False
        }
    }

    Context "Command doesn't get excluded category" {
        BeforeAll {
            $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'Cat1'
            $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'Cat2'

            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_cat1 -Category 'Cat1'
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_cat2 -Category 'Cat2'
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'Cat1', 'Cat2' -Confirm:$false

            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_testjob_cat1, dbatoolsci_testjob_cat2 -Confirm:$false
        }
        It "Should not return excluded job" {
            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -ExcludeCategory 'Cat2' | Where-Object { $_.Name -match "dbatoolsci_testjob" }
            $results.name -contains "dbatoolsci_testjob_cat2" | Should -Be $False
        }
    }

    Context "Command gets jobs when databases are specified" {
        BeforeAll {
            $jobName1 = "dbatoolsci_dbfilter_$(Get-Random)"
            $jobName2 = "dbatoolsci_dbfilter_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName1 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName1 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName1 -StepName "TSQL-y" -Subsystem TransactSql -Database "tempdb"
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName1 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"

            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName2 -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName2 -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName2 -StepName "TSQL-y" -Subsystem TransactSql -Database "model"
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName2 -StepName "TSQL-z" -Subsystem TransactSql -Database "master"
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName1, $jobName2 -Confirm:$false
        }
        It "Returns result with single database" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $global:instance2 -Database tempdb
            $resultSingleDatabase.Count | Should -BeGreaterOrEqual 1
        }
        It "Returns job result for Database: tempdb" {
            $resultSingleDatabase = Get-DbaAgentJob -SqlInstance $global:instance2 -Database tempdb
            $resultSingleDatabase.name -contains $jobName1 | Should -BeTrue
        }
        It "Returns both jobs with double database" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $global:instance2 -Database tempdb, model
            $resultMultipleDatabases.Count | Should -BeGreaterOrEqual 2
        }
        It "Includes job result for Database: model" {
            $resultMultipleDatabases = Get-DbaAgentJob -SqlInstance $global:instance2 -Database tempdb, model
            $resultMultipleDatabases.name -contains $jobName2 | Should -BeTrue
        }
    }
}
