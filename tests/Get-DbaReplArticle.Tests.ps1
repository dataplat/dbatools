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
}
