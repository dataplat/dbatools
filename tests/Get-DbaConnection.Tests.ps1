#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaConnection",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns the proper transport" {
        BeforeAll {
            $results = Get-DbaConnection -SqlInstance $TestConfig.InstanceSingle
        }

        It "returns a valid AuthScheme" {
            foreach ($result in $results) {
                $result.AuthScheme | Should -BeIn "NTLM", "Kerberos", "SQL"
            }
        }

        It "Returns output with expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "MostRecentSessionId",
                "ConnectTime",
                "Transport",
                "ProtocolType",
                "ProtocolVersion",
                "EndpointId",
                "EncryptOption",
                "AuthScheme",
                "NodeAffinity",
                "Reads",
                "Writes",
                "LastRead",
                "LastWrite",
                "PacketSize",
                "ClientNetworkAddress",
                "ClientTcpPort",
                "ServerNetworkAddress",
                "ServerTcpPort",
                "ConnectionId",
                "ParentConnectionId",
                "MostRecentSqlHandle"
            )
            foreach ($prop in $expectedProperties) {
                $results[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}