#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaDbMirrorMonitor",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When adding mirror monitor" {
        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
        }

        It "Adds the mirror monitor" {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
            $results.MonitorStatus | Should -Be "Added"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "MonitorStatus"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "MonitorStatus property contains expected value" {
            $result.MonitorStatus | Should -Be "Added"
        }
    }
}