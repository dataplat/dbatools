param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentJobCategory
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have CategoryType parameter" {
            $CommandUnderTest | Should -HaveParameter CategoryType -Type System.String[]
        }
        It "Should have JobCategory parameter" {
            $CommandUnderTest | Should -HaveParameter JobCategory -Type System.String[]
        }
        It "Should have AgentCategory parameter" {
            $CommandUnderTest | Should -HaveParameter AgentCategory -Type System.String[]
        }
        It "Should have OperatorCategory parameter" {
            $CommandUnderTest | Should -HaveParameter OperatorCategory -Type System.String[]
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

Describe "Copy-DbaAgentJobCategory Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci test category'
    }

    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category 'dbatoolsci test category' -Confirm:$false
    }

    Context "Command copies jobs properly" {
        It "returns one success" {
            $results = Copy-DbaAgentJobCategory -Source $global:instance2 -Destination $global:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Successful"
        }

        It "does not overwrite" {
            $results = Copy-DbaAgentJobCategory -Source $global:instance2 -Destination $global:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Skipped"
        }
    }
}
