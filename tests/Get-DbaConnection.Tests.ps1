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
        It "returns a valid AuthScheme" {
            $results = Get-DbaConnection -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            foreach ($result in $results) {
                $result.AuthScheme | Should -BeIn "NTLM", "Kerberos", "SQL"
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should have the expected properties" {
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
                "MostRecentSqlHandle",
                "RowError",
                "RowState",
                "Table",
                "ItemArray",
                "HasErrors"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}