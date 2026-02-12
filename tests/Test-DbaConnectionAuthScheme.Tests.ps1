#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaConnectionAuthScheme",
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
                "Kerberos",
                "Ntlm",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns the proper transport" {
        It "returns ntlm auth scheme" {
            $script:results = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.InstanceSingle
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                $script:results.AuthScheme | Should -Be 'ntlm'
            } else {
                $script:results.AuthScheme | Should -Be 'KERBEROS'
            }

        }

        Context "Output validation" {
            It "Returns output of the expected type" {
                $script:results | Should -Not -BeNullOrEmpty
                @($script:results)[0] | Should -BeOfType System.Data.DataRow
            }

            It "Has the expected default display properties" {
                if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
                $defaultProps = @($script:results)[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Transport", "AuthScheme")
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }

            It "Has all additional properties available" {
                if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProps = @("SessionId", "MostRecentSessionId", "ConnectTime", "ProtocolType", "ProtocolVersion", "EndpointId", "EncryptOption", "NodeAffinity", "NumReads", "NumWrites", "LastRead", "LastWrite", "PacketSize", "ClientNetworkAddress", "ClientTcpPort", "ServerNetworkAddress", "ServerTcpPort", "ConnectionId", "ParentConnectionId", "MostRecentSqlHandle")
                foreach ($prop in $expectedProps) {
                    @($script:results)[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be available"
                }
            }
        }
    }
}