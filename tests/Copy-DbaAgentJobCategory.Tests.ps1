#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CategoryType",
                "JobCategory",
                "AlertCategory",
                "OperatorCategory",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up test category for the integration tests
        $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceCopy1 -Category "dbatoolsci test category"
        $alertCategoryNames = "dbatoolsci alert category", "dbatoolsci other alert category"
        $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceCopy1 -Category $alertCategoryNames

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created categories
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceCopy1 -Category "dbatoolsci test category"
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceCopy2 -Category "dbatoolsci test category"
        $null = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Category $alertCategoryNames | Remove-DbaAgentAlertCategory

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CategoryType",
                "JobCategory",
                "AlertCategory",
                "OperatorCategory",
                "Force",
                "EnableException"
            )

            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "When copying job categories" {
        It "Returns successful results" {
            $splatCopyCategory = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                JobCategory = "dbatoolsci test category"
            }

            $results = Copy-DbaAgentJobCategory @splatCopyCategory
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Successful"
        }

        It "Does not overwrite existing categories" {
            $splatSecondCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                JobCategory = "dbatoolsci test category"
            }

            $secondCopyResults = Copy-DbaAgentJobCategory @splatSecondCopy
            $secondCopyResults.Name | Should -Be "dbatoolsci test category"
            $secondCopyResults.Status | Should -Be "Skipped"
        }
    }

    Context "When copying alert categories" {
        It "Copies only the requested alert category" {
            # The parameter was declared as -AgentCategory while the code filtered on $AlertCategory, so the filter
            # was never applied and every alert category was copied (#10607). It is now -AlertCategory with the old
            # name as an alias.
            $splatCopyAlertCategory = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                AlertCategory = "dbatoolsci alert category"
            }
            $results = Copy-DbaAgentJobCategory @splatCopyAlertCategory
            $results.Name | Should -Be "dbatoolsci alert category"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceCopy2 -Category $alertCategoryNames).Name | Should -Be "dbatoolsci alert category"
        }
    }
}
