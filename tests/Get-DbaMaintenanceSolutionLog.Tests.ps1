#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaintenanceSolutionLog",
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
                "LogType",
                "Since",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: parsing real IndexOptimize logs requires the Ola Hallengren maintenance
    # solution installed and a populated CommandLog / on-disk log directory, which the standalone
    # InstanceSingle does not provide - that leg is DEFERRED-TO-GATE on a maintenance-solution
    # fixture. -SqlInstance is Mandatory and the command connects before any other check, so there
    # is no connection-independent leg. What IS deterministic on any reachable instance is the
    # unsupported-LogType guard: only IndexOptimize is parseable, so any other LogType warns once
    # and moves on without output. The check runs immediately after Connect-DbaInstance and does
    # not depend on instance state. This command is read-only ([CmdletBinding()] with no
    # SupportsShouldProcess), so no WhatIf is passed.
    BeforeAll {
        $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
    }

    Context "Guarding an unsupported LogType" {
        It "Warns once and returns nothing for a LogType other than IndexOptimize" {
            $splatUnsupported = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LogType         = "DatabaseBackup"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Get-DbaMaintenanceSolutionLog @splatUnsupported)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Parsing DatabaseBackup is not supported at the moment"
        }
    }
}