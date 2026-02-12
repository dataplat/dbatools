#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Repair-DbaDbMirror",
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
    Context "Output validation" -Skip:($true) {
        # Repair-DbaDbMirror requires database mirroring infrastructure (two instances with mirroring endpoints
        # and a mirrored database in suspended state). This is not available in standard CI environments.
        # Skipping output validation as there is no safe way to create a suspended mirror in test.

        It "Returns output of the documented type" {
            # Repair-DbaDbMirror returns Microsoft.SqlServer.Management.Smo.Database objects
            # This test is skipped because mirroring infrastructure is required
            $true | Should -BeTrue
        }
    }
}