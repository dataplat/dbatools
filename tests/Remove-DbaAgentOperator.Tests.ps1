$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operator', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $Operator = "DBA"
        New-DbaAgentOperator -SqlInstance $script:instance2 -Operator $Operator
    }

    AfterAll {
        $null = Remove-DbaAgentOperator -SqlInstance $script:instance2 -Operator $Operator
    }

    Context "Remove Agent Operator is remvoed properly" {
        It "Should have no operator with that name" {
            Remove-DbaAgentOperator -SqlInstance $script:instance2 -Operator $Operator
            $results = (Get-DbaAgentOperator -SqlInstance $script:instance2 -Operator $Operator).Count
            $results | Should Be 0
        }
    }
}