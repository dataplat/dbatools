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
                "AppendConnectionString",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "When creating a connection string" {
        BeforeAll {
            $result = New-DbaConnectionString -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return a connection string" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should contain Data Source" {
            $result | Should -Match "Data Source"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a string" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.String]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String"
        }
    }
}