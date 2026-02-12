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
            $sourceConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1 -ConfigName RemoteQueryTimeout
            $destConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout
            $sourceConfigValue = $sourceConfig.ConfiguredValue
            $destConfigValue = $destConfig.ConfiguredValue

            # Set different values to ensure they don't match
            if ($sourceConfigValue -and $destConfigValue) {
                $newValue = $sourceConfigValue + $destConfigValue
                $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout -Value $newValue
            }
        }

        AfterAll {
            if ($destConfigValue -and $destConfigValue -ne $sourceConfigValue) {
                $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout -Value $destConfigValue
            }
        }

        It "Should start with different values" {
            $config1 = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Not -Be $config2.ConfiguredValue
        }

        It "Should copy successfully" {
            $script:results = Copy-DbaSpConfigure -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout
            $script:results.Status | Should -Be "Successful"
        }

        It "Should retain the same properties after copy" {
            $config1 = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Be $config2.ConfiguredValue
        }

        It "Should not modify the source configuration" {
            $newConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1 -ConfigName RemoteQueryTimeout
            $newConfig.ConfiguredValue | Should -Be $sourceConfigValue
        }

        It "Returns output of the expected type" {
            if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:results[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $script:results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected values for standard migration properties" {
            if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:results[0].Type | Should -Be "Configuration Value"
            $script:results[0].Status | Should -BeIn @("Successful", "Skipped")
            $script:results[0].SourceServer | Should -Not -BeNullOrEmpty
            $script:results[0].DestinationServer | Should -Not -BeNullOrEmpty
        }
    }
}