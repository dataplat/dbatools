param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentProxy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentProxy
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have ProxyAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProxyAccount -Type String[]
        }
        It "Should have ExcludeProxyAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeProxyAccount -Type String[]
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

Describe "Copy-DbaAgentProxy Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_proxy  @proxy_name = 'dbatoolsci_agentproxy', @enabled = 1, @credential_name = 'dbatoolsci_credential'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $server.Query($sql)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $server.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $server.Query($sql)
    }

    Context "Copies Agent Proxy" {
        It "returns one successful result" {
            $results = Copy-DbaAgentProxy -Source $script:instance2 -Destination $script:instance3 -ProxyAccount dbatoolsci_agentproxy
            $results.Count | Should -Be 1
            $results.Status | Should -Be "Successful"
        }

        It "creates one proxy on the destination" {
            $results = Get-DbaAgentProxy -SqlInstance $script:instance3 -Proxy dbatoolsci_agentproxy
            $results.Count | Should -Be 1
        }
    }
}
