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

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "SqlInstallDate")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has SqlInstallDate as a DbaDateTime value" {
            $result.SqlInstallDate | Should -Not -BeNullOrEmpty
            $result.SqlInstallDate.GetType().FullName | Should -Be "Dataplat.Dbatools.Utility.DbaDateTime"
        }
    }

    Context "Output validation with IncludeWindows" {
        BeforeAll {
            $resultWindows = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows
        }

        It "Has the expected default display properties with WindowsInstallDate" {
            if (-not $resultWindows) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $resultWindows.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "SqlInstallDate", "WindowsInstallDate")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}