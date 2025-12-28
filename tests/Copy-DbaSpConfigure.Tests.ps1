#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSpConfigure",
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
                "ConfigName",
                "ExcludeConfigName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When copying configuration with the same properties" {
        BeforeAll {
            $sourceConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy1 -ConfigName RemoteQueryTimeout
            $destConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout
            $sourceConfigValue = $sourceConfig.ConfiguredValue
            $destConfigValue = $destConfig.ConfiguredValue

            # Set different values to ensure they don't match
            if ($sourceConfigValue -and $destConfigValue) {
                $newValue = $sourceConfigValue + $destConfigValue
                $null = Set-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout -Value $newValue
            }
        }

        AfterAll {
            if ($destConfigValue -and $destConfigValue -ne $sourceConfigValue) {
                $null = Set-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout -Value $destConfigValue
            }
        }

        It "Should start with different values" {
            $config1 = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Not -Be $config2.ConfiguredValue
        }

        It "Should copy successfully" {
            $results = Copy-DbaSpConfigure -Source $TestConfig.instanceCopy1 -Destination $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout
            $results.Status | Should -Be "Successful"
        }

        It "Should retain the same properties after copy" {
            $config1 = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Be $config2.ConfiguredValue
        }

        It "Should not modify the source configuration" {
            $newConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.instanceCopy1 -ConfigName RemoteQueryTimeout
            $newConfig.ConfiguredValue | Should -Be $sourceConfigValue
        }
    }
}