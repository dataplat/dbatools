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

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaCmConnection -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Connection.ConnectionManager]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'CimRM',
                'CimDCOM',
                'Wmi',
                'PowerShellRemoting'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional timestamp properties" {
            $result.PSObject.Properties.Name | Should -Contain 'LastCimRM'
            $result.PSObject.Properties.Name | Should -Contain 'LastCimDCOM'
            $result.PSObject.Properties.Name | Should -Contain 'LastWmi'
            $result.PSObject.Properties.Name | Should -Contain 'LastPowerShellRemoting'
        }

        It "Has credential management properties" {
            $result.PSObject.Properties.Name | Should -Contain 'KnownBadCredentials'
            $result.PSObject.Properties.Name | Should -Contain 'DisableBadCredentialCache'
        }
    }
}