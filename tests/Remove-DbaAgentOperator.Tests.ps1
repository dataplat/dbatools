$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operator', 'ServerObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $email1 = "test1$($random)@test.com"
        $email2 = "test2$($random)@test.com"
    }

    AfterAll {
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email1 -Confirm:$false
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email2 -Confirm:$false
    }

    Context "Remove Agent Operator is removed properly" {
        It "Should have no operator with that name" {
            Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email1 -Confirm:$false
            $results = (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $email1).Count
            $results | Should Be 0
        }

        It "Pipeline command" {
            $results = $instance2 | Remove-DbaAgentOperator -Operator $email2 -Confirm:$false
            $results | Should -BeNullOrEmpty
        }
    }
}