param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentOperator
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Operator",
            "ExcludeOperator",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Remove-DbaAgentOperator Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
        $email1 = "test1$($random)@test.com"
        $email2 = "test2$($random)@test.com"
    }

    AfterAll {
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email1
        $null = Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email2
    }

    Context "Remove Agent Operator is removed properly" {
        It "Should have no operator with that name" {
            Remove-DbaAgentOperator -SqlInstance $instance2 -Operator $email1
            $results = (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $email1).Count
            $results | Should -Be 0
        }

        It "supports piping SQL Agent operator" {
            $operatorName = "dbatoolsci_test_$(Get-Random)"
            $null = New-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName | Remove-DbaAgentOperator
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName) | Should -BeNullOrEmpty
        }
    }
}
