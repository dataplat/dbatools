#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceInstallDate",
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
                "Credential",
                "IncludeWindows",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets SQL Server Install Date" {
        It "Gets results" {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets SQL Server Install Date and Windows Install Date" {
        It "Gets results" {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SqlInstallDate'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation with -IncludeWindows" {
        BeforeAll {
            $result = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows -EnableException
        }

        It "Includes WindowsInstallDate property when -IncludeWindows is specified" {
            $result.PSObject.Properties.Name | Should -Contain 'WindowsInstallDate' -Because "property 'WindowsInstallDate' should be included with -IncludeWindows switch"
        }

        It "Has all expected properties including Windows install date" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SqlInstallDate',
                'WindowsInstallDate'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in display with -IncludeWindows"
            }
        }
    }
}