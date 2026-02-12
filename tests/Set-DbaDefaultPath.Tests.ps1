#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDefaultPath",
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
                "Type",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $oldBackupDirectory = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).BackupDirectory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Set-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle -Type Backup -Path $oldBackupDirectory

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "returns proper information" {
        It "Backup returns the correct value" {
            $results = Set-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle -Type Backup -Path $TestConfig.Temp
            $results.Backup | Should -BeExactly $TestConfig.Temp
        }

        Context "Output validation" {
            It "Returns output of the expected type" {
                $results | Should -Not -BeNullOrEmpty
                $results | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                $results | Should -Not -BeNullOrEmpty
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Data", "Log", "Backup")
                foreach ($prop in $expectedProps) {
                    $results.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }
        }
    }
}