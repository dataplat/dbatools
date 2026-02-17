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
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
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
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ServerName",
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
                "IsRunningDefaultValue",
                "Parent",
                "ConfigName",
                "Property"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}