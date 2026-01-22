#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaConnectionString",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "AccessToken",
                "ApplicationIntent",
                "BatchSeparator",
                "ClientName",
                "ConnectTimeout",
                "Database",
                "EncryptConnection",
                "FailoverPartner",
                "IsActiveDirectoryUniversalAuth",
                "LockTimeout",
                "MaxPoolSize",
                "MinPoolSize",
                "MultipleActiveResultSets",
                "MultiSubnetFailover",
                "NetworkProtocol",
                "NonPooledConnection",
                "PacketSize",
                "PooledConnectionLifetime",
                "SqlExecutionModes",
                "StatementTimeout",
                "TrustServerCertificate",
                "WorkstationId",
                "Legacy",
                "AppendConnectionString"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaConnectionString -SqlInstance "localhost,1433"
        }

        It "Returns System.String (connection string)" {
            $result | Should -BeOfType [System.String]
        }

        It "Returns a valid connection string with expected components" {
            $result | Should -Match "Data Source="
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>