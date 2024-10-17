param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentOperator
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type String[]
        }
        It "Should have ExcludeOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeOperator -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Operator[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
        It "Should have Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type SwitchParameter
        }
        It "Should have Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type SwitchParameter
        }
        It "Should have ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Should have WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Should have InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Should have OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Should have OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Should have PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type SwitchParameter
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type SwitchParameter
        }
    }
}

Describe "Remove-DbaAgentOperator Integration Tests" -Tag "IntegrationTests" {
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
            $results | Should -Be 0
        }

        It "supports piping SQL Agent operator" {
            $operatorName = "dbatoolsci_test_$(Get-Random)"
            $null = New-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName | Remove-DbaAgentOperator -Confirm:$false
            (Get-DbaAgentOperator -SqlInstance $instance2 -Operator $operatorName) | Should -BeNullOrEmpty
        }
    }
}
