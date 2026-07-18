#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplArticle",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip UnitTests on pwsh because command is not present.

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Publication",
                "Schema",
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: removing an article needs a configured replication publisher/publication,
    # which the GitHub Actions replication harness provides (gh-actions-repl-*) - that live leg is
    # DEFERRED-TO-REPL-HARNESS. What IS characterizable with no replication configured is the
    # input guard the source runs before touching any instance: neither -SqlInstance nor
    # -InputObject supplied is rejected. The guard is connection-independent (probe-verified). This
    # command also emits a "Could not load replication libraries" warning when the Replication
    # assemblies are absent (as in the standalone drop) and not when they are present, so the total
    # warning count is environment dependent - the assertion checks that the guard message is among
    # the warnings (Should -Contain) rather than pinning an exact count. WhatIf is belt-and-braces
    # on this destructive (drop article) command; the guard returns before any gated action.
    Context "Guarding the input parameters" {
        It "Warns with the input guard and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaReplArticle @splatNoInput)
            $result.Count | Should -Be 0

            # strip the bracketed [timestamp]/[function] prefix from each warning; the input guard
            # message must be present regardless of the environment-dependent replication-library warning
            $payloads = $warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
            $payloads | Should -Contain "You must specify either SqlInstance or InputObject"
        }
    }
}
