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

    Context "Command actually works" {
        BeforeAll {
            $trueResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber $versionMajor
            $falseResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber -1
        }

        It "Should have correct properties" {
            $expectedProps = @("ComputerName", "Version", "Exists")
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should -Be $true
        }

        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should -Be $false
        }
    }

    Context "Output validation" {
        BeforeAll {
            $versionToTest = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor
            $result = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber $versionToTest
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "Version", "Exists")
            foreach ($prop in $expectedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}