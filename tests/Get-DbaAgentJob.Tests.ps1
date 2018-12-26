$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentJob).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'ExcludeDisabledJobs', 'EnableException', 'Database', 'Category'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
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
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object {$_.Name -match "dbatoolsci"}
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
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -ExcludeDisabledJobs | Where-Object {$_.Name -match "dbatoolsci"}
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
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -ExcludeJob dbatoolsci_testjob  | Where-Object {$_.Name -match "dbatoolsci"}
        It "Should not return excluded job" {
            $results.name -contains "dbatoolsci_testjob" | Should Be $False
        }
    }
}