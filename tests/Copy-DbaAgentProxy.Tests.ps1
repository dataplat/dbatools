#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaAgentProxy" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentProxy
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ProxyAccount",
                "ExcludeProxyAccount",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaAgentProxy" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_proxy  @proxy_name = 'dbatoolsci_agentproxy', @enabled = 1, @credential_name = 'dbatoolsci_credential'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)
    }

    Context "When copying agent proxy between instances" {
        BeforeAll {
            $results = Copy-DbaAgentProxy -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -ProxyAccount dbatoolsci_agentproxy
        }

        It "Should return one successful result" {
            $results.Status.Count | Should -Be 1
            $results.Status | Should -Be "Successful"
        }

        It "Should create the proxy on the destination" {
            $proxyResults = Get-DbaAgentProxy -SqlInstance $TestConfig.instance3 -Proxy dbatoolsci_agentproxy
            $proxyResults.Name.Count | Should -Be 1
        }
    }
}
