$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "connection is properly made" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -ApplicationIntent ReadOnly

        It "returns the proper name" {
            $server.Name -eq $script:instance1 | Should Be $true
        }

        It "returns more than one database" {
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString -match "ApplicationIntent=ReadOnly" | Should Be $true
        }

        It "sets StatementTimeout to 0" {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 -StatementTimeout 0

            $server.ConnectionContext.StatementTimeout | Should Be 0
        }

        It "sets connectioncontext parameters that are provided" {
            $params = @{
                'BatchSeparator' = 'GO'
                'ConnectTimeout' = 1
                'Database' = 'master'
                'LockTimeout' = 1
                'MaxPoolSize' = 20
                'MinPoolSize' = 1
                'NetworkProtocol' = 'TcpIp'
                'PacketSize' = 4096
                'PooledConnectionLifetime' = 600
                'WorkstationId' = 'MadeUpServer'
                'SqlExecutionModes' = 'ExecuteSql'
                'StatementTimeout' = 0
            }

            $server = Connect-DbaInstance -SqlInstance $script:instance1 @params

            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq 'Database') {
                    $propName = 'DatabaseName'
                } else {
                    $propName = $param.Key
                }

                $server.ConnectionContext.$propName | Should Be $param.Value
            }
        }
    }
}