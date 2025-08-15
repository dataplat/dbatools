#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $configs = $server.Query("sp_configure")
            $remoteQueryTimeout = $configs | Where-Object name -match "remote query timeout"
        }

        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.instance1
            $results.count -eq $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.instance1 -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should -Be 2
        }

        It "returns two results less than all data" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.instance1 -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count -eq $configs.count - 2
        }

        It "matches the output of sp_configure" {
            $results = Get-DbaSpConfigure -SqlInstance $TestConfig.instance1 -Name RemoteQueryTimeout
            $results.ConfiguredValue -eq $remoteQueryTimeout.config_value | Should -Be $true
            $results.RunningValue -eq $remoteQueryTimeout.run_value | Should -Be $true
        }
    }
}