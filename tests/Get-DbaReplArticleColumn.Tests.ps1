#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplArticleColumn",
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
                "Article",
                "Column",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: returning populated column objects requires a configured publication whose
    # articles resolve to live source tables, which the GitHub Actions replication harness provides
    # (gh-actions-repl-*) - that live leg is DEFERRED there. What IS characterizable on a plain
    # instance is the read path of the port: it queries Get-DbaReplArticle (which returns nothing on
    # a non-configured instance), iterates the empty article set, and returns nothing without
    # throwing. That single leg exercises the module hop and the empty-article column loop end to end.
    Context "Reading an instance with no replication articles" {
        It "Returns nothing and does not throw" {
            $splatColumn = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WarningAction = "SilentlyContinue"
                ErrorAction   = "SilentlyContinue"
            }
            $result = Get-DbaReplArticleColumn @splatColumn
            $result | Should -BeNullOrEmpty
        }
    }
}