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

    # The begin-block replication library load and the connect failure both produce warnings that
    # must reach the caller carrying the command's own name. Both are observable with no SQL Server
    # reachable at all, so this leg measures the streams rather than a live topology.
    Context "Warning stream when the instance cannot be reached" {
        BeforeAll {
            # 127.0.0.1,1 is refused instantly where the port is closed, but a dropped packet would
            # otherwise wait out the 15-second default. The setting is process-wide, so AfterAll
            # restores it.
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "Warns under the command name and returns nothing instead of throwing" {
            $splatUnreachable = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                WarningVariable = "connectWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = Get-DbaReplArticle @splatUnreachable

            $result | Should -BeNullOrEmpty
            $connectWarning | Should -Not -BeNullOrEmpty
            ($connectWarning | ForEach-Object { $PSItem.ToString() }) -join "`n" | Should -Match ([regex]::Escape("[Get-DbaReplArticle] Error occurred while establishing connection to"))
        }
    }

    Context "Connection failures remain isolated to each piped record" {
        BeforeAll {
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "Emits one command-owned connection warning for each unreachable record" {
            $warnings = @()
            $splatPipedUnreachable = @{
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = @(
                $TestConfig.InstanceUnreachable, $TestConfig.InstanceUnreachable |
                    Get-DbaReplArticle @splatPipedUnreachable
            )
            $ownedWarnings = @(
                $warnings | Where-Object {
                    $PSItem.ToString() -match "\[Get-DbaReplArticle\]\s+Error occurred while establishing connection to"
                }
            )

            $result | Should -BeNullOrEmpty
            $ownedWarnings.Count | Should -Be 2
        }
    }
}
