#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Connect-DbaInstance",
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
                "Database",
                "ApplicationIntent",
                "AzureUnsupported",
                "BatchSeparator",
                "ClientName",
                "ConnectTimeout",
                "EncryptConnection",
                "FailoverPartner",
                "LockTimeout",
                "MaxPoolSize",
                "MinPoolSize",
                "MinimumVersion",
                "MultipleActiveResultSets",
                "MultiSubnetFailover",
                "NetworkProtocol",
                "NonPooledConnection",
                "PacketSize",
                "PooledConnectionLifetime",
                "SqlExecutionModes",
                "StatementTimeout",
                "TrustServerCertificate",
                "AllowTrustServerCertificate",
                "WorkstationId",
                "AlwaysEncrypted",
                "AppendConnectionString",
                "SqlConnectionOnly",
                "AzureDomain",
                "Tenant",
                "AccessToken",
                "DedicatedAdminConnection",
                "DisableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate alias" {
        It "Should contain the alias: cdi" {
            (Get-Alias cdi) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        Get-DbaConnectedInstance | Disconnect-DbaInstance
        Clear-DbaConnectionPool
    }

    if ($env:azuredbpasswd -eq "failstoooften") {
        Context "Connect to Azure" {
            BeforeAll {
                $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential ($TestConfig.azuresqldblogin, $securePassword)
            }

            It "Should login to Azure" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $s.Name | Should -match "psdbatools.database.windows.net"
                $s.DatabaseEngineType | Should -Be "SqlAzureDatabase"
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
            }

            It "Should keep the same database context again" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbname"
                $results.dbname | Should -Be "test"
            }

            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $server = Connect-DbaInstance -SqlInstance $s
                $server.Query("select db_name() as dbname").dbname | Should -Be "test"
            }
        }
    }

    Context "connection is properly made using a string" {
        BeforeAll {
            $params = @{
                BatchSeparator           = "GO"
                ConnectTimeout           = 1
                Database                 = "tempdb"
                LockTimeout              = 1
                MaxPoolSize              = 20
                MinPoolSize              = 1
                NetworkProtocol          = "TcpIp"
                PacketSize               = 4096
                PooledConnectionLifetime = 600
                WorkstationId            = "MadeUpServer"
                SqlExecutionModes        = "ExecuteSql"
                StatementTimeout         = 0
                ApplicationIntent        = "ReadOnly"
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 @params
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "sets connectioncontext parameters that are provided" {
            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq "Database") {
                    $propName = "DatabaseName"
                } else {
                    $propName = $param.Key
                }
                $server.ConnectionContext.PSObject.Properties[$propName].Value | Should -Be $param.Value
            }
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
        }

        It "keeps the same database context" {
            $null = $server.Databases["msdb"].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }

        It "sets StatementTimeout to 0" {
            $server.ConnectionContext.StatementTimeout | Should -Be 0
        }
    }

    Context "connection is properly made using a connection string" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$($TestConfig.InstanceMulti1);Initial Catalog=tempdb;Integrated Security=True"
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            # Before #8962 this changed the context to msdb
            $null = $server.Databases["msdb"].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }
    }

    if ($TestConfig.InstanceMulti1 -match "localhost") {
        Context "connection is properly made using a dot" {
            BeforeAll {
                $newinstance = $TestConfig.InstanceMulti1.Replace("localhost", ".")
                $server = Connect-DbaInstance -SqlInstance $newinstance
            }

            It "returns the proper name" {
                $server.Name | Should -Be "NP:$newinstance"
            }

            It "returns more than one database" {
                $server.Databases.Name.Count | Should -BeGreaterThan 1
            }

            It "keeps the same database context" {
                $null = $server.Databases["msdb"].Tables.Count
                # This currently fails!
                #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            }
        }
    }

    Context "connection is properly made using a connection object" {
        BeforeAll {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value "instance.ComputerName"
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$($TestConfig.InstanceMulti1);Initial Catalog=tempdb;Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
        }

        It "returns the proper name" {
            $server.Name | Should -Be $TestConfig.InstanceMulti1
        }

        It "returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "keeps the same database context" {
            $null = $server.Databases["msdb"].Tables.Count
            # This currently fails!
            #$server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }
    }

    Context "connection is properly cloned from an existing connection" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        }

        AfterAll {
            $server | Disconnect-DbaInstance
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }

        It "clones when using parameter ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -ApplicationIntent ReadOnly
            $server.ConnectionContext.ApplicationIntent | Should -BeNullOrEmpty
            $serverClone.ConnectionContext.ApplicationIntent | Should -Be "ReadOnly"
        }

        It "clones when using parameter NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -NonPooledConnection
            $server.ConnectionContext.NonPooledConnection | Should -Be $false
            $serverClone.ConnectionContext.NonPooledConnection | Should -Be $true
        }

        It "clones when using parameter StatementTimeout" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -StatementTimeout 123
            $server.ConnectionContext.StatementTimeout | Should -Be (Get-DbatoolsConfigValue -FullName "sql.execution.timeout")
            $serverClone.ConnectionContext.StatementTimeout | Should -Be 123
        }

        It "clones when using parameter DedicatedAdminConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -DedicatedAdminConnection
            $server.ConnectionContext.ServerInstance | Should -Not -Match "^ADMIN:"
            $serverClone.ConnectionContext.ServerInstance | Should -Match "^ADMIN:"
            $serverClone | Disconnect-DbaInstance
        }

        It "clones when using Backup-DabInstace" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb
            if ($results.FullName) {
                Remove-Item -Path $results.FullName -ErrorAction SilentlyContinue
            }

            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb -WarningVariable warn
            $warn | Should -BeNullOrEmpty

            if ($results.FullName) {
                Remove-Item -Path $results.FullName -ErrorAction SilentlyContinue
            }
        }
    }

    Context "multiple connections are properly made using strings" {
        It "returns the proper names" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $server[0].Name | Should -Be $TestConfig.InstanceMulti1
            $server[1].Name | Should -Be $TestConfig.InstanceMulti2
        }
    }

    Context "multiple dedicated admin connections are properly made using strings" {
        # This might fail if a parallel test uses DAC - how can we ensure that this is the only test that is run?
        It "opens and closes the connections" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server[0].Name | Should -Be "ADMIN:$($TestConfig.InstanceMulti1)"
            $server[1].Name | Should -Be "ADMIN:$($TestConfig.InstanceMulti2)"
            $null = $server | Disconnect-DbaInstance
            # DAC is not reopened in the background
            Start-Sleep -Seconds 10
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server.Count | Should -Be 2
            $null = $server | Disconnect-DbaInstance
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -DisableException
        }

        AfterAll {
            $result | Disconnect-DbaInstance
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Server]
        }

        It "Has the dbatools-specific added properties" {
            $expectedProps = @(
                'ComputerName',
                'IsAzure',
                'DbaInstanceName',
                'SqlInstance',
                'NetPort',
                'ConnectedAs'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }

        It "Has standard SMO Server properties" {
            $result.PSObject.Properties.Name | Should -Contain 'Name'
            $result.PSObject.Properties.Name | Should -Contain 'Databases'
            $result.PSObject.Properties.Name | Should -Contain 'Logins'
            $result.PSObject.Properties.Name | Should -Contain 'ConnectionContext'
            $result.PSObject.Properties.Name | Should -Contain 'VersionMajor'
        }
    }

    Context "Output with -SqlConnectionOnly" {
        BeforeAll {
            $result = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlConnectionOnly -DisableException
        }

        AfterAll {
            if ($result) {
                $result.Close()
                $result.Dispose()
            }
        }

        It "Returns SqlConnection when -SqlConnectionOnly specified" {
            $result | Should -BeOfType [Microsoft.Data.SqlClient.SqlConnection]
        }

        It "Has SqlConnection properties" {
            $result.PSObject.Properties.Name | Should -Contain 'State'
            $result.PSObject.Properties.Name | Should -Contain 'ConnectionString'
            $result.PSObject.Properties.Name | Should -Contain 'Database'
        }
    }
}