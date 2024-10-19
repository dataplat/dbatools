param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentProxy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentProxy
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ProxyAccount",
                "ExcludeProxyAccount",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Copy-DbaAgentProxy Integration Tests" -Tag "IntegrationTests" {

    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_proxy  @proxy_name = 'dbatoolsci_agentproxy', @enabled = 1, @credential_name = 'dbatoolsci_credential'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $global:instance3
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $global:instance3
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)
    }

    Context "Copies Agent Proxy" {
        It "returns one successful result" {
            $results = Copy-DbaAgentProxy -Source $global:instance2 -Destination $global:instance3 -ProxyAccount dbatoolsci_agentproxy
            $results.Count | Should -Be 1
            $results.Status | Should -Be "Successful"
        }

        It "creates one proxy on the destination" {
            $results = Get-DbaAgentProxy -SqlInstance $global:instance3 -Proxy dbatoolsci_agentproxy
            $results.Count | Should -Be 1
        }
    }
}
