$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operator', 'ExcludeOperator', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
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

        It "supports piping SQL Agent operator" {
            $operatorName = "dbatoolsci_test_$(get-random)"
            $null = New-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName ) | Should -Not -BeNullOrEmpty
            Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName | Remove-DbaAgentOperator -Confirm:$false
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName ) | Should -BeNullOrEmpty
        }
    }
}
