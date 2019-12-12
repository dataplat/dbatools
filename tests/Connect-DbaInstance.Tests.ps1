$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ApplicationIntent', 'AzureUnsupported', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'FailoverPartner', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'MinimumVersion', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AppendConnectionString', 'SqlConnectionOnly', 'AzureDomain', 'AuthenticationType', 'Tenant', 'Thumbprint', 'Store', 'DisableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate alias" {
        It "Should contain the alias: cdi" {
            (Get-Alias cdi) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    if ($env:azuredbpasswd -eq "failstoooften") {
        Context "Connect to Azure" {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($script:azuresqldblogin, $securePassword)

            It "Should login to Azure" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $s.Name | Should -match 'psdbatools.database.windows.net'
                $s.DatabaseEngineType | Should -Be 'SqlAzureDatabase'
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be 'test'
            }

            It "Should keep the same database context again" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be 'test'
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be 'test'
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $server = Connect-DbaInstance -SqlInstance $s
                $server.Query("select db_name() as dbname").dbname | Should -Be 'test'
            }
        }
    }

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

        It "connects using a connection string" {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$script:instance1;Initial Catalog=tempdb;Integrated Security=True;"
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "sets connectioncontext parameters that are provided" {
            $params = @{
                'BatchSeparator'           = 'GO'
                'ConnectTimeout'           = 1
                'Database'                 = 'master'
                'LockTimeout'              = 1
                'MaxPoolSize'              = 20
                'MinPoolSize'              = 1
                'NetworkProtocol'          = 'TcpIp'
                'PacketSize'               = 4096
                'PooledConnectionLifetime' = 600
                'WorkstationId'            = 'MadeUpServer'
                'SqlExecutionModes'        = 'ExecuteSql'
                'StatementTimeout'         = 0
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