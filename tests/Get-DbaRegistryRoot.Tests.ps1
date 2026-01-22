#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegistryRoot",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaRegistryRoot -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
            $regexPath = "Software\\Microsoft\\Microsoft SQL Server"
        }

        It "returns at least one named instance if more than one result is returned" {
            $named = $results | Where-Object SqlInstance -match '\\'
            $named.SqlInstance.Count -gt 0 | Should -BeTrue
        }

        It "returns non-null values" {
            foreach ($result in $results) {
                $result.Hive | Should -Not -BeNullOrEmpty
                $result.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }

        It "matches Software\Microsoft\Microsoft SQL Server" {
            foreach ($result in $results) {
                $result.RegistryRoot -match $regexPath | Should -BeTrue
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaRegistryRoot -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Hive",
                "Path",
                "RegistryRoot"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}