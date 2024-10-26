#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaAgentJobCategory" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category 'dbatoolsci test category'
    }
    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category 'dbatoolsci test category' -Confirm:$false
    }

    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentJobCategory
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CategoryType",
                "JobCategory",
                "AgentCategory",
                "OperatorCategory",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }

    Context "When copying job categories" {
        It "Returns successful results" {
            $splat = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                JobCategory = "dbatoolsci test category"
            }

            $results = Copy-DbaAgentJobCategory @splat
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Successful"
        }

        It "Does not overwrite existing categories" {
            $splatSecondCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                JobCategory = "dbatoolsci test category"
            }

            $secondCopyResults = Copy-DbaAgentJobCategory @splatSecondCopy
            $secondCopyResults.Name | Should -Be "dbatoolsci test category"
            $secondCopyResults.Status | Should -Be "Skipped"
        }
    }
}
