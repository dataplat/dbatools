#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublication",
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
                "Name",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: returning populated Publication objects requires a configured publisher with
    # published databases, which the GitHub Actions replication harness provides (gh-actions-repl-*) -
    # that live leg is DEFERRED there. What IS characterizable on a plain instance is the read path of
    # the command: it connects with -MinimumVersion 9, enumerates the accessible, non-system databases,
    # tests each database's ReplicationOptions for Published/MergePublished, and (finding none published)
    # returns nothing without throwing. That single leg exercises the live connection, the IsAccessible
    # database enumeration, and the not-published skip branch end to end.
    Context "Reading an instance with no replication publications" {
        It "Returns nothing and does not throw" {
            $splatPublication = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WarningAction = "SilentlyContinue"
                ErrorAction   = "SilentlyContinue"
            }
            $result = Get-DbaReplPublication @splatPublication
            $result | Should -BeNullOrEmpty
        }
    }
}
