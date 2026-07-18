#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaReplArticle",
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
                "Publication",
                "Schema",
                "Name",
                "Filter",
                "CreationScriptOptions",
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
    # NOTE ON COVERAGE: adding an article to a publication requires a configured replication
    # publisher/publication, which the GitHub Actions replication harness provides (gh-actions-repl-*)
    # - that live leg is DEFERRED-TO-GATE. What IS characterizable with no replication configured is
    # the Filter input guard the source runs before touching any instance: a -Filter that begins
    # with WHERE is rejected. The guard uses Stop-Function, so with -EnableException it throws before
    # any connection, making it deterministic and connection-independent (probe-verified). The other
    # early guard (CreationScriptOptions type) is not pinned here: it depends on the
    # Microsoft.SqlServer.Replication.CreationScriptOptions type being loaded, which is environment
    # dependent, so it belongs with the replication-harness coverage.
    BeforeAll {
        # [char]39 supplies the single quotes the source wraps WHERE in, without putting literal
        # single quotes in the test source
        $q = [char]39
    }

    Context "Guarding the Filter input" {
        It "Throws before any connection when the Filter begins with WHERE" {
            $splatBadFilter = @{
                SqlInstance     = "dbatoolsci-nonexistent"
                Database        = "dbatoolsci_db"
                Publication     = "dbatoolsci_pub"
                Name            = "dbatoolsci_article"
                Filter          = "WHERE 1 = 1"
                EnableException = $true
                WhatIf          = $true
            }
            $err = { Add-DbaReplArticle @splatBadFilter } | Should -Throw -PassThru
            $err.Exception.Message | Should -Be "Filter should not include the word ${q}WHERE${q}"
        }
    }
}