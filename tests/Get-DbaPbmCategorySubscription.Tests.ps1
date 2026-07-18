#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategorySubscription",
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
                "InputObject",
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
    # NOTE ON COVERAGE: retrieving Policy-Based Management objects needs the PBM SMO assemblies, which
    # are Desktop-only - the live retrieval is DEFERRED-TO-GATE (it runs on the integrationPs51/Desktop
    # gate). What IS deterministic is the PowerShell Core refusal. Note this command has no edition
    # guard of its own: when -SqlInstance is supplied it resolves the store through the nested
    # Get-DbaPbmStore, and THAT command carries the edition guard, so on Core the refusal warning
    # surfaces here and nothing is emitted. This leg runs on the Core gate (integrationPs7) where the
    # guard fires; it is skipped on Desktop, where the guard does not fire and the live retrieval is the
    # deferred leg. Read-only command, no WhatiF. Probe-verified on Core.
    Context "Guarding on PowerShell Core" {
        It "Warns and returns nothing on PowerShell Core" -Skip:($PSVersionTable.PSEdition -ne "Core") {
            $splatCoreGuard = @{
                SqlInstance     = "dbatoolsci-core-guard"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Get-DbaPbmCategorySubscription @splatCoreGuard)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "This command is not supported on Linux or macOS"
        }
    }
}
