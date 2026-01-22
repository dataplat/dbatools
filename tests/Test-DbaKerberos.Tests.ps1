#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaKerberos",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have SqlInstance in Instance parameter set" {
            $command = Get-Command $CommandName
            $instanceSet = $command.ParameterSets | Where-Object Name -eq "Instance"
            $instanceSet.Parameters.Name | Should -Contain "SqlInstance"
        }

        It "Should have ComputerName in Computer parameter set" {
            $command = Get-Command $CommandName
            $computerSet = $command.ParameterSets | Where-Object Name -eq "Computer"
            $computerSet.Parameters.Name | Should -Contain "ComputerName"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaKerberos -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "Check",
                "Category",
                "Status",
                "Details",
                "Remediation"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns multiple check results" {
            $result.Count | Should -BeGreaterThan 1 -Because "Test-DbaKerberos should perform multiple diagnostic checks"
        }

        It "ComputerName property is not null or empty" {
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Check property is not null or empty" {
            $result[0].Check | Should -Not -BeNullOrEmpty
        }

        It "Category property is not null or empty" {
            $result[0].Category | Should -Not -BeNullOrEmpty
        }

        It "Status property contains valid values" {
            $validStatuses = @("Pass", "Fail", "Warning")
            $result[0].Status | Should -BeIn $validStatuses
        }
    }

    Context "Output with -ComputerName parameter" {
        BeforeAll {
            $result = Test-DbaKerberos -ComputerName $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "Check",
                "Category",
                "Status",
                "Details",
                "Remediation"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "InstanceName should be null when using ComputerName parameter" {
            # When testing at computer level, InstanceName should be null
            $result[0].InstanceName | Should -BeNullOrEmpty
        }
    }
}
