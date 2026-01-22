#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaManagementObject",
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
                "VersionNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $versionMajor = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber $versionMajor -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'Version',
                'Exists'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $trueResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber $versionMajor
            $falseResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber -1
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should -Be $true
        }

        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should -Be $false
        }
    }
}