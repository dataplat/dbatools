#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCmObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ClassName",
                "Query",
                "ComputerName",
                "Credential",
                "Namespace",
                "DoNotUse",
                "Force",
                "SilentlyContinue",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns proper information" {
        It "Returns a bias that's an int" {
            (Get-DbaCmObject -ClassName Win32_TimeZone).Bias | Should -BeOfType [int]
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone -EnableException
        }

        It "Returns WMI or CIM object type" {
            # Can be either ManagementObject (WMI) or CimInstance (CIM) depending on connection method
            $isValidType = ($result -is [System.Management.ManagementObject]) -or ($result -is [Microsoft.Management.Infrastructure.CimInstance])
            $isValidType | Should -Be $true -Because "output should be either ManagementObject or CimInstance"
        }

        It "Returns object with properties from the queried class" {
            # Win32_TimeZone should have standard properties
            $result.PSObject.Properties.Name | Should -Contain 'Bias' -Because "Win32_TimeZone should have Bias property"
            $result.PSObject.Properties.Name | Should -Contain 'StandardName' -Because "Win32_TimeZone should have StandardName property"
        }
    }

    Context "Output Validation with Query parameter" {
        BeforeAll {
            $result = Get-DbaCmObject -Query "SELECT * FROM Win32_OperatingSystem" -EnableException
        }

        It "Returns WMI or CIM object when using -Query parameter" {
            $isValidType = ($result -is [System.Management.ManagementObject]) -or ($result -is [Microsoft.Management.Infrastructure.CimInstance])
            $isValidType | Should -Be $true -Because "output should be either ManagementObject or CimInstance"
        }

        It "Returns object with properties from Win32_OperatingSystem" {
            $result.PSObject.Properties.Name | Should -Contain 'Caption' -Because "Win32_OperatingSystem should have Caption property"
            $result.PSObject.Properties.Name | Should -Contain 'Version' -Because "Win32_OperatingSystem should have Version property"
        }
    }
}