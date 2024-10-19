param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentJobCategory
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CategoryType",
                "JobCategory",
                "AgentCategory",
                "OperatorCategory",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
