$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentJob).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'NoDisabledJobs', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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
    }
    Context "Command gets no disabled jobs" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_disabled -Disabled
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
        }
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -NoDisabledJobs | Where-Object {$_.Name -match "dbatoolsci"}
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
    Context "Command stops when can't connect" {
        It "Should warn cannot connect to MadeUpServer" {
            { Get-DbaAgentJob -SqlInstance MadeUpServer -EnableException } | Should Throw "Can't connect to MadeUpServer"
        }
    }
}