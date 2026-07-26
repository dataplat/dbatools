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
    Context "Connection failures remain isolated to each piped record" {
        BeforeAll {
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "Emits one command-owned Failure warning for each unreachable record" {
            $warnings = @()
            $result = @(
                $TestConfig.InstanceUnreachable, $TestConfig.InstanceUnreachable |
                    Get-DbaReplPublication -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            )
            $ownedWarnings = @(
                $warnings | Where-Object { $PSItem.ToString() -match "\[Get-DbaReplPublication\]\s+Failure(?:\s+\||$)" }
            )

            $result | Should -BeNullOrEmpty
            $ownedWarnings.Count | Should -Be 2
        }
    }
}
