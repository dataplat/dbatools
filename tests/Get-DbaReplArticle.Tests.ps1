#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplArticle",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: returning populated article objects requires a configured publication with
    # articles, which the GitHub Actions replication harness provides (gh-actions-repl-*) - that
    # live leg is DEFERRED there. What IS characterizable on a plain instance is the read path of
    # the port: it connects, enumerates the accessible databases, queries each for publications
    # (of which a non-configured instance has none), and returns nothing without throwing. That
    # single leg exercises the module hop, the begin-block library load, the live connection, the
    # IsAccessible database enumeration, and the empty-publication article loop end to end.
    Context "Reading an instance with no replication articles" {
        It "Returns nothing and does not throw" {
            $splatArticle = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = Get-DbaReplArticle @splatArticle
            $result | Should -BeNullOrEmpty
        }
    }
}