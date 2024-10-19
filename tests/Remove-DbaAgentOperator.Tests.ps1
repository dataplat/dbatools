param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentOperator
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator
        }
        It "Should have ExcludeOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeOperator
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
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
