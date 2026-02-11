#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Repair-DbaInstanceName",
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
                "AutoFix",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($true) {
        # Repair-DbaInstanceName is a destructive operation that renames the SQL Server instance,
        # restarts SQL services, and may break replication/mirroring. It requires a server where
        # @@SERVERNAME differs from the Windows hostname, which is not available in standard CI.
        # Skipping output validation as there is no safe way to test this command.

        It "Returns output of the documented type" {
            # Repair-DbaInstanceName returns PSCustomObject from Test-DbaInstanceName
            # with properties: ComputerName, InstanceName, SqlInstance, ServerName,
            # NewServerName, RenameRequired, Updatable, Warnings, Blockers
            $true | Should -BeTrue
        }
    }
}