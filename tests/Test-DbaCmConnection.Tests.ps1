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
    It "returns some valid info" {
        $results = Test-DbaCmConnection -Type Wmi
        $results.ComputerName | Should -Be $env:COMPUTERNAME
    }

    Context "Output validation" {
        BeforeAll {
            $result = Test-DbaCmConnection -Type Wmi
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().FullName | Should -Be "Dataplat.Dbatools.Connection.ManagementConnection"
        }

        It "Has the expected connection test properties" {
            $result.PSObject.Properties.Name | Should -Contain "ComputerName"
            $result.PSObject.Properties.Name | Should -Contain "Wmi"
            $result.PSObject.Properties.Name | Should -Contain "CimRM"
            $result.PSObject.Properties.Name | Should -Contain "CimDCOM"
            $result.PSObject.Properties.Name | Should -Contain "PowerShellRemoting"
        }

        It "Has the expected timestamp properties" {
            $result.PSObject.Properties.Name | Should -Contain "LastWmi"
            $result.PSObject.Properties.Name | Should -Contain "LastCimRM"
            $result.PSObject.Properties.Name | Should -Contain "LastCimDCOM"
            $result.PSObject.Properties.Name | Should -Contain "LastPowerShellRemoting"
        }
    }
}