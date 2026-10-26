#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-BackupAncientHistory",
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
                "FileNameStub",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When the instance cannot be reached" {
        It "Warns and returns nothing" {
            # The begin block stops when the connection fails, but the process block used to run anyway and called
            # methods on the missing server object (#10655). The command name does not match the *-Dba* default for
            # the warning variable, so it is passed explicitly.
            $splatNoHost = @{
                SqlInstance     = "dbatoolsci-nohost"
                Database        = "master"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnings"
            }
            $results = Get-BackupAncientHistory @splatNoHost
            $results | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}
