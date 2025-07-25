$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ApplicationIntent', 'AzureUnsupported', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'FailoverPartner', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'MinimumVersion', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AlwaysEncrypted', 'AppendConnectionString', 'SqlConnectionOnly', 'AzureDomain', 'Tenant', 'AccessToken', 'DedicatedAdminConnection', 'DisableException'
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
            $cred = New-Object System.Management.Automation.PSCredential ($TestConfig.azuresqldblogin, $securePassword)

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

    Context "connection is properly made using a string" {
        BeforeAll {
            $params = @{
                'BatchSeparator'           = 'GO'
                'ConnectTimeout'           = 1
                'Database'                 = 'tempdb'
                'LockTimeout'              = 1
                'MaxPoolSize'              = 20
                'MinPoolSize'              = 1
                'NetworkProtocol'          = 'TcpIp'
                'PacketSize'               = 4096
                'PooledConnectionLifetime' = 600
                'WorkstationId'            = 'MadeUpServer'
                'SqlExecutionModes'        = 'ExecuteSql'
                'StatementTimeout'         = 0
                'ApplicationIntent'        = 'ReadOnly'
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 @params
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.instance1
        }

        It "sets connectioncontext parameters that are provided" {
            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq 'Database') {
                    $propName = 'DatabaseName'
                } else {
                    $propName = $param.Key
                }
                $server.ConnectionContext.$propName | Should -Be $param.Value
            }
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
        }

        It "keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }

        It "sets StatementTimeout to 0" {
            $server.ConnectionContext.StatementTimeout | Should -Be 0
        }
    }

    Context "connection is properly made using a connection string" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$($TestConfig.instance1);Initial Catalog=tempdb;Integrated Security=True"
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.instance1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            # Before #8962 this changed the context to msdb
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }
    }

    if ($TestConfig.instance1 -match 'localhost') {
        Context "connection is properly made using a dot" {
            BeforeAll {
                $newinstance = $TestConfig.instance1.Replace("localhost", ".")
                $server = Connect-DbaInstance -SqlInstance $newinstance
            }

            It "returns the proper name" {
                $server.Name | Should -Be "NP:$newinstance"
            }

            It "returns more than one database" {
                $server.Databases.Name.Count | Should -BeGreaterThan 1
            }

            It "keeps the same database context" {
                $null = $server.Databases['msdb'].Tables.Count
                # This currently fails!
                #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
            }
        }
    }

    Context "connection is properly made using a connection object" {
        BeforeAll {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$($TestConfig.instance1);Initial Catalog=tempdb;Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.instance1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            # This currently fails!
            #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }
    }

    Context "connection is properly cloned from an existing connection" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'master'
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }

        It "clones when using parameter ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -ApplicationIntent ReadOnly
            $server.ConnectionContext.ApplicationIntent | Should -BeNullOrEmpty
            $serverClone.ConnectionContext.ApplicationIntent | Should -Be 'ReadOnly'
        }

        It "clones when using parameter NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -NonPooledConnection
            $server.ConnectionContext.NonPooledConnection | Should -Be $false
            $serverClone.ConnectionContext.NonPooledConnection | Should -Be $true
        }

        It "clones when using parameter StatementTimeout" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -StatementTimeout 123
            $server.ConnectionContext.StatementTimeout | Should -Be (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout')
            $serverClone.ConnectionContext.StatementTimeout | Should -Be 123
        }

        It "clones when using parameter DedicatedAdminConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -DedicatedAdminConnection
            $server.ConnectionContext.ServerInstance | Should -Not -Match '^ADMIN:'
            $serverClone.ConnectionContext.ServerInstance | Should -Match '^ADMIN:'
            $serverClone | Disconnect-DbaInstance
        }

        It "clones when using Backup-DabInstace" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -Database tempdb
            $null = Backup-DbaDatabase -SqlInstance $server -Database msdb
            $null = Backup-DbaDatabase -SqlInstance $server -Database msdb -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "multiple connections are properly made using strings" {
        It "returns the proper names" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1, $TestConfig.instance2
            $server[0].Name | Should -Be $TestConfig.instance1
            $server[1].Name | Should -Be $TestConfig.instance2
        }
    }

    Context "multiple dedicated admin connections are properly made using strings" {
        # This might fail if a parallel test uses DAC - how can we ensure that this is the only test that is run?
        It "opens and closes the connections" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -DedicatedAdminConnection
            $server[0].Name | Should -Be "ADMIN:$($TestConfig.instance1)"
            $server[1].Name | Should -Be "ADMIN:$($TestConfig.instance2)"
            $null = $server | Disconnect-DbaInstance
            # DAC is not reopened in the background
            Start-Sleep -Seconds 10
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -DedicatedAdminConnection
            $server.Count | Should -Be 2
            $null = $server | Disconnect-DbaInstance
        }
    }
}
