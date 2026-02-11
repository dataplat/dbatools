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
    Context "Output validation" {
        BeforeAll {
            $result = New-DbaConnectionString -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType System.String
        }

        It "Returns a valid connection string containing Data Source" {
            $result | Should -Match "Data Source"
        }
    }
}