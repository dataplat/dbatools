$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'CategoryType', 'JobCategory', 'AgentCategory', 'OperatorCategory', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }
    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }

    Context "Command copies jobs properly" {
        It "returns one success" {
            $results = Copy-DbaAgentJobCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Successful"
        }

        It "does not overwrite" {
            $results = Copy-DbaAgentJobCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Skipped"
        }
    }
}