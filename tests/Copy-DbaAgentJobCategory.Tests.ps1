#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJobCategory",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci test category"
    }
    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci test category" -Confirm:$false
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance3 -Category "dbatoolsci test category" -Confirm:$false
    }

    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "When copying job categories" {
        It "Returns successful results" {
            $splatCopyCategory = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                JobCategory = "dbatoolsci test category"
            }

            $results = Copy-DbaAgentJobCategory @splatCopyCategory
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
