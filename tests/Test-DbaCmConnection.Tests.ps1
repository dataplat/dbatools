#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Type",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $results = Test-DbaCmConnection -Type Wmi
    }

    It "returns some valid info" {
        $results.ComputerName | Should -Be $env:COMPUTERNAME
    }

    Context "Output validation" {
        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "Dataplat.Dbatools.Connection.ManagementConnection"
        }

        It "Has the expected connection test properties" {
            $results.PSObject.Properties.Name | Should -Contain "ComputerName"
            $results.PSObject.Properties.Name | Should -Contain "Wmi"
            $results.PSObject.Properties.Name | Should -Contain "CimRM"
            $results.PSObject.Properties.Name | Should -Contain "CimDCOM"
            $results.PSObject.Properties.Name | Should -Contain "PowerShellRemoting"
        }

        It "Has the expected timestamp properties" {
            $results.PSObject.Properties.Name | Should -Contain "LastWmi"
            $results.PSObject.Properties.Name | Should -Contain "LastCimRM"
            $results.PSObject.Properties.Name | Should -Contain "LastCimDCOM"
            $results.PSObject.Properties.Name | Should -Contain "LastPowerShellRemoting"
        }
    }
}