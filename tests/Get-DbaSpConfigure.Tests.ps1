#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "ExcludeName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Get configuration" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $configs = $server.Query("sp_configure")
            $remoteQueryTimeout = $configs | Where-Object name -match "remote query timeout"
        }

        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle
            $results.count -eq $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should -Be 2
        }

        It "returns two results less than all data" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count -eq $configs.count - 2
        }

        It "matches the output of sp_configure" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout
            $results.ConfiguredValue -eq $remoteQueryTimeout.config_value | Should -Be $true
            $results.RunningValue -eq $remoteQueryTimeout.run_value | Should -Be $true
        }

        It "Returns output of the expected type" {
            $result = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $result = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "DisplayName",
                "Description",
                "IsAdvanced",
                "IsDynamic",
                "MinValue",
                "MaxValue",
                "ConfiguredValue",
                "RunningValue",
                "DefaultValue",
                "IsRunningDefaultValue"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include excluded properties in default display" {
            $result = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("ServerName", "Parent", "ConfigName", "Property")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }
    }
}