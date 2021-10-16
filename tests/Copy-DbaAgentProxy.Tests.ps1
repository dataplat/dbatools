$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'ProxyAccount', 'ExcludeProxyAccount', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
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
        $results = Copy-DbaAgentProxy -Source $script:instance2 -Destination $script:instance3 -ProxyAccount dbatoolsci_agentproxy

        It "returns one results" {
            $results.Count -eq 1
            $results.Status -eq "Successful"
        }

        It "return one result that's skipped" {
            $results = Get-DbaAgentProxy -SqlInstance $script:instance3 -Proxy dbatoolsci_agentproxy
            $results.Count -eq 1
        }
    }
}