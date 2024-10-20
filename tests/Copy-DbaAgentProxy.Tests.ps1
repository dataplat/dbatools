param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentProxy" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentProxy
        }
        $paramList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'ProxyAccount',
            'ExcludeProxyAccount',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Copies Agent Proxy" {
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
