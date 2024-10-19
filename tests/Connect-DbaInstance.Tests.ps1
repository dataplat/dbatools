param($ModuleName = 'dbatools')

Describe "Connect-DbaInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Connect-DbaInstance
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ApplicationIntent as a parameter" {
            $CommandUnderTest | Should -HaveParameter ApplicationIntent
        }
        It "Should have AzureUnsupported as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureUnsupported
        }
        It "Should have BatchSeparator as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator
        }
        It "Should have ClientName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ClientName
        }
        It "Should have ConnectTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectTimeout
        }
        It "Should have EncryptConnection as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptConnection
        }
        It "Should have FailoverPartner as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverPartner
        }
        It "Should have LockTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter LockTimeout
        }
        It "Should have MaxPoolSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxPoolSize
        }
        It "Should have MinPoolSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter MinPoolSize
        }
        It "Should have MinimumVersion as a parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumVersion
        }
        It "Should have MultipleActiveResultSets as a parameter" {
            $CommandUnderTest | Should -HaveParameter MultipleActiveResultSets
        }
        It "Should have MultiSubnetFailover as a parameter" {
            $CommandUnderTest | Should -HaveParameter MultiSubnetFailover
        }
        It "Should have NetworkProtocol as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetworkProtocol
        }
        It "Should have NonPooledConnection as a parameter" {
            $CommandUnderTest | Should -HaveParameter NonPooledConnection
        }
        It "Should have PacketSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter PacketSize
        }
        It "Should have PooledConnectionLifetime as a parameter" {
            $CommandUnderTest | Should -HaveParameter PooledConnectionLifetime
        }
        It "Should have SqlExecutionModes as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlExecutionModes
        }
        It "Should have StatementTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout
        }
        It "Should have TrustServerCertificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter TrustServerCertificate
        }
        It "Should have WorkstationId as a parameter" {
            $CommandUnderTest | Should -HaveParameter WorkstationId
        }
        It "Should have AlwaysEncrypted as a parameter" {
            $CommandUnderTest | Should -HaveParameter AlwaysEncrypted
        }
        It "Should have AppendConnectionString as a parameter" {
            $CommandUnderTest | Should -HaveParameter AppendConnectionString
        }
        It "Should have SqlConnectionOnly as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlConnectionOnly
        }
        It "Should have AzureDomain as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureDomain
        }
        It "Should have Tenant as a parameter" {
            $CommandUnderTest | Should -HaveParameter Tenant
        }
        It "Should have AccessToken as a parameter" {
            $CommandUnderTest | Should -HaveParameter AccessToken
        }
        It "Should have DedicatedAdminConnection as a parameter" {
            $CommandUnderTest | Should -HaveParameter DedicatedAdminConnection
        }
        It "Should have DisableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisableException
        }
    }

    Context "Validate alias" {
        It "Should contain the alias: cdi" {
            (Get-Alias cdi).ResolvedCommandName | Should -Be 'Connect-DbaInstance'
        }
    }

    Context "Connect to Azure" -Skip:($env:azuredbpasswd -ne "failstoooften") {
        BeforeAll {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($global:azuresqldblogin, $securePassword)
        }

        It "Should login to Azure" {
            $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
            $s.Name | Should -Match 'psdbatools.database.windows.net'
            $s.DatabaseEngineType | Should -Be 'SqlAzureDatabase'
        }

        It "Should keep the same database context" {
            $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
            $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
            $results.dbname | Should -Be 'test'
        }
    }

    Context "Connection is properly made using a string" {
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
            $server = Connect-DbaInstance -SqlInstance $global:instance1 @params
        }

        It "Returns the proper name" {
            $server.Name | Should -Be $global:instance1
        }

        It "Sets ConnectionContext parameters that are provided" {
            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq 'Database') {
                    $propName = 'DatabaseName'
                } else {
                    $propName = $param.Key
                }
                $server.ConnectionContext.$propName | Should -Be $param.Value
            }
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }

        It "Sets StatementTimeout to 0" {
            $server.ConnectionContext.StatementTimeout | Should -Be 0
        }
    }

    Context "Connection is properly made using a connection string" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$global:instance1;Initial Catalog=tempdb;Integrated Security=True"
        }

        It "Returns the proper name" {
            $server.Name | Should -Be $global:instance1
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }
    }

    Context "Connection is properly made using a dot" -Skip:($global:instance1 -notmatch 'localhost') {
        BeforeAll {
            $newinstance = $global:instance1.Replace("localhost", ".")
            $server = Connect-DbaInstance -SqlInstance $newinstance
        }

        It "Returns the proper name" {
            $server.Name | Should -Be "NP:$newinstance"
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
        }
    }

    Context "Connection is properly made using a connection object" {
        BeforeAll {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$global:instance1;Initial Catalog=tempdb;Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
        }

        It "Returns the proper name" {
            $server.Name | Should -Be $global:instance1
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
        }
    }

    Context "Connection is properly cloned from an existing connection" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
        }

        It "Clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'master'
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }

        It "Clones when using parameter ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -ApplicationIntent ReadOnly
            $server.ConnectionContext.ApplicationIntent | Should -BeNullOrEmpty
            $serverClone.ConnectionContext.ApplicationIntent | Should -Be 'ReadOnly'
        }

        It "Clones when using parameter NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -NonPooledConnection
            $server.ConnectionContext.NonPooledConnection | Should -Be $false
            $serverClone.ConnectionContext.NonPooledConnection | Should -Be $true
        }

        It "Clones when using parameter StatementTimeout" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -StatementTimeout 123
            $server.ConnectionContext.StatementTimeout | Should -Be (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout')
            $serverClone.ConnectionContext.StatementTimeout | Should -Be 123
        }

        It "Clones when using parameter DedicatedAdminConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -DedicatedAdminConnection
            $server.ConnectionContext.ServerInstance | Should -Not -Match '^ADMIN:'
            $serverClone.ConnectionContext.ServerInstance | Should -Match '^ADMIN:'
            $serverClone | Disconnect-DbaInstance
        }

        It "Clones when using Backup-DbaDatabase" {
            $server = Connect-DbaInstance -SqlInstance $global:instance1 -Database tempdb
            $null = Backup-DbaDatabase -SqlInstance $server -Database msdb
            $null = Backup-DbaDatabase -SqlInstance $server -Database msdb -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Multiple connections are properly made using strings" {
        It "Returns the proper names" {
            $server = Connect-DbaInstance -SqlInstance $global:instance1, $global:instance2
            $server[0].Name | Should -Be $global:instance1
            $server[1].Name | Should -Be $global:instance2
        }
    }

    Context "Multiple dedicated admin connections are properly made using strings" {
        It "Opens and closes the connections" {
            $server = Connect-DbaInstance -SqlInstance $global:instance1, $global:instance2 -DedicatedAdminConnection
            $server[0].Name | Should -Be "ADMIN:$global:instance1"
            $server[1].Name | Should -Be "ADMIN:$global:instance2"
            $null = $server | Disconnect-DbaInstance
            Start-Sleep -Seconds 10
            $server = Connect-DbaInstance -SqlInstance $global:instance1, $global:instance2 -DedicatedAdminConnection
            $server.Count | Should -Be 2
            $null = $server | Disconnect-DbaInstance
        }
    }
}
