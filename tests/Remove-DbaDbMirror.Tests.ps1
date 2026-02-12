#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMirror",
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
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($env:APPVEYOR) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Find a mirrored database to test with
            $mirroredDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Where-Object IsMirroringEnabled -eq $true | Select-Object -First 1
            if ($mirroredDb) {
                $result = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceSingle -Database $mirroredDb.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no mirrored database available to test" }
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no mirrored database available to test" }
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Removed"
        }
    }
}