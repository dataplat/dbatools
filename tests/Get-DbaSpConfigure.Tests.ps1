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

            # sp_configure only lists the basic options unless "show advanced options" is turned on,
            # which is 25 rows against the 86 the command returns. sys.configurations lists them all
            # without changing the configuration of the instance, so it is the comparable set.
            # The sp_configure result is kept for the test below, which reads its config_value and
            # run_value columns.
            $allConfigs = $server.Query("SELECT name FROM sys.configurations")
        }

        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle
            $results.Count | Should -Be $allConfigs.Count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should -Be 2
        }

        It "returns two results less than all data" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count | Should -Be ($allConfigs.Count - 2)
        }

        It "matches the output of sp_configure" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Name RemoteQueryTimeout
            $results.ConfiguredValue -eq $remoteQueryTimeout.config_value | Should -Be $true
            $results.RunningValue -eq $remoteQueryTimeout.run_value | Should -Be $true
        }
    }
}