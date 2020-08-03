$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'Database', 'Category', 'ExcludeDisabledJobs', 'EnableException', 'ExcludeCategory'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command gets jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should get 2 dbatoolsci jobs" {
            $results.count | Should Be 2
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
        It "Should get a specific job" {
            $results.name | Should Be "dbatoolsci_testjob"
        }

    }
    Context "Command gets no disabled jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -ExcludeDisabledJobs | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should return only enabled jobs" {
            $results.enabled -contains $False | Should Be $False
        }
    }
    Context "Command doesn't get excluded job" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -ExcludeJob dbatoolsci_testjob | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should not return excluded job" {
            $results.name -contains "dbatoolsci_testjob" | Should Be $False
        }
    }
    Context "Command doesn't get excluded category" {
        BeforeAll {
            $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'Cat1'
            $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'Cat2'

            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_cat1 -Category 'Cat1'
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_cat2 -Category 'Cat2'
        }
        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'Cat1', 'Cat2'

            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_cat1, dbatoolsci_testjob_cat2
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -ExcludeCategory 'Cat2' | Where-Object { $_.Name -match "dbatoolsci" }
        It "Should not return excluded job" {
            $results.name -contains "dbatoolsci_testjob_cat2" | Should Be $False
        }
    }
    Context "Command gets jobs with specified database" {
        BeforeAll {
            $jobName = "dbatoolsci_dbfilter_(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-y" -Subsystem TransactSql -Database "tempdb"
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-z" -Subsystem TransactSql -Database "master"
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Database tempdb
        It "Returns results" {
            $results.Count | Should -BeGreaterOrEqual 1
        }
        It "Should return job for Database: tempdb" {
            $results.name -contains $jobName | Should -BeTrue
        }
    }
}            $jobName = "dbatoolsci_dbfilter_(Get-Random)"
$null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Disabled
$null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-x" -Subsystem TransactSql -Database "msdb"
$null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-y" -Subsystem TransactSql -Database "tempdb"
$null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName "TSQL-z" -Subsystem TransactSql -Database "master"
}
AfterAll {
    $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
}
$results = Get-DbaAgentJob -SqlInstance $script:instance2 -Database tempdb
It "Returns results" {
    $results.Count | Should -BeGreaterOrEqual 1
}
It "Should return job for Database: tempdb" {
    $results.name -contains $jobName | Should -BeTrue
}
}
}