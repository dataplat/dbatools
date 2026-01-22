#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaSpn",
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
    Context "When getting SPN information" {
        BeforeAll {
            $results = Test-DbaSpn -ComputerName $TestConfig.InstanceSingle
        }

        It "Returns some results" {
            $results.RequiredSPN | Should -Not -BeNullOrEmpty
        }

        It "Has the required properties for all results" {
            foreach ($result in $results) {
                $result.RequiredSPN | Should -Match "MSSQLSvc"
                $result.TcpEnabled | Should -Be $true
                $result.IsSet | Should -BeOfType [bool]
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaSpn -ComputerName $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlProduct",
                "InstanceServiceAccount",
                "RequiredSPN",
                "IsSet",
                "Cluster",
                "TcpEnabled",
                "Port",
                "DynamicPort",
                "Warning",
                "Error"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Does not include Credential or DomainName properties in output" {
            $actualProps = $result[0].PSObject.Properties.Name
            $actualProps | Should -Not -Contain "Credential" -Because "Credential is excluded by Select-DefaultView"
            $actualProps | Should -Not -Contain "DomainName" -Because "DomainName is excluded by Select-DefaultView"
        }
    }
}