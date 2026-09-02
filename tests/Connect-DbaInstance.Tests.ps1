#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Connect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $script:hasCredentialSspiProvider = $null -ne ("Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider" -as [type])
    # A dedicated admin connection to an instance on the machine running the tests takes a different path
    # than one to a remote instance: it goes to ADMIN:localhost and forces TrustServerCertificate, because
    # the certificate of the instance does not have to match "localhost" (#10254). That path can only be
    # exercised where the instance really is local, which is the case on the CI runners and not in a lab
    # of remote instances. The value decides a Skip, so it has to exist at discovery time.
    $script:instanceIsLocalHost = ([DbaInstanceParameter]$TestConfig.InstanceMulti1).IsLocalHost
    # Azure SQL Database is the only engine that refuses to switch the database of a connection it has
    # already opened - it answers a USE with error 40508 and wants a new connection instead. Every branch
    # that depends on that can therefore only be covered against a real one, which a lab configuration
    # supplies through AzureSqlDbServer. Everywhere else these tests skip themselves. The value decides a
    # Skip, so it has to exist at discovery time.
    $script:hasAzureSqlDb = -not [string]::IsNullOrWhiteSpace($TestConfig.AzureSqlDbServer)
}

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
                "AuthenticationType",
                "DedicatedAdminConnection",
                "IsNewConnectionReference",
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

    Context "Failover partner retry behavior" {
        BeforeAll {
            function New-MockConnectionContext {
                param(
                    [string]$ConnectionString,
                    [string[]]$AttemptErrors
                )

                $sqlConnectionObject = [PSCustomObject]@{
                    ConnectionString = $ConnectionString
                }

                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    AttemptErrors       = $AttemptErrors
                    AttemptCount        = 0
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                    $this.AttemptCount++
                    $this.ConnectionString = $this.SqlConnectionObject.ConnectionString
                    $attemptIndex = $this.AttemptCount - 1
                    if ($attemptIndex -lt $this.AttemptErrors.Count -and $this.AttemptErrors[$attemptIndex]) {
                        throw (New-Object -TypeName System.Exception -ArgumentList $this.AttemptErrors[$attemptIndex])
                    }
                } -Force

                $connectionContext
            }

            function New-MockServer {
                param(
                    [string]$ConnectionString,
                    [string[]]$AttemptErrors
                )

                [PSCustomObject]@{
                    ConnectionContext = New-MockConnectionContext -ConnectionString $ConnectionString -AttemptErrors $AttemptErrors
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                [PSCustomObject]@{ }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockServer -ConnectionString $script:mockConnectionString -AttemptErrors $script:attemptErrors
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "retries connection string inputs when failover partner requires Initial Catalog" {
            $script:mockConnectionString = "Data Source=sqlmirror;Integrated Security=True;Failover Partner=mirrorpartner"
            $script:attemptErrors = @(
                "Use of key 'Failover Partner' requires the key 'Initial Catalog' to be present."
            )

            $result = Connect-DbaInstance -SqlInstance $script:mockConnectionString -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Initial Catalog=master"
        }

        It "retries with Initial Catalog after a trust certificate retry exposes the failover partner requirement" {
            $script:mockConnectionString = "Data Source=sqlmirror;Integrated Security=True;FailoverPartner=mirrorpartner;Trust Server Certificate=False"
            $script:attemptErrors = @(
                "The certificate chain was issued by an authority that is not trusted.",
                "Use of key 'Failover Partner' requires the key 'Initial Catalog' to be present."
            )

            $result = Connect-DbaInstance -SqlInstance "sqlmirror" -FailoverPartner "mirrorpartner" -AllowTrustServerCertificate -TrustServerCertificate:$false -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Trust Server Certificate=True"
            $result.ConnectionString | Should -Match "Initial Catalog=master"
        }
    }

    Context "Access token connection behavior" {
        BeforeAll {
            function New-MockAccessTokenServer {
                $sqlConnectionObject = [PSCustomObject]@{
                    ConnectionString = "Data Source=sqltoken;Integrated Security=True"
                }
                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $sqlConnectionObject.ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name NonPooledConnection -MemberType ScriptProperty -Value {
                    $true
                } -SecondValue {
                    param($value)
                    $script:nonPooledConnectionSetterCalls++
                    throw "Property NonPooledConnection cannot be changed or read after a connection string has been set."
                } -Force

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                } -Force

                [PSCustomObject]@{
                    ConnectionContext = $connectionContext
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                [PSCustomObject]@{
                    ConnectionString = "Data Source=sqltoken;Integrated Security=True"
                    AccessToken      = $null
                }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.Data.SqlClient.SqlConnection"
            }
            Mock New-Object {
                [PSCustomObject]@{ }
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockAccessTokenServer
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "does not reapply NonPooledConnection when AccessToken already uses a SqlConnection" {
            $script:nonPooledConnectionSetterCalls = 0

            $result = Connect-DbaInstance -SqlInstance "sqltoken" -AccessToken "token" -NonPooledConnection -SqlConnectionOnly

            $result.ConnectionString | Should -Be "Data Source=sqltoken;Integrated Security=True"
            $script:nonPooledConnectionSetterCalls | Should -Be 0
        }
    }

    Context "AuthenticationType behavior" {
        BeforeAll {
            function New-MockAuthenticationServer {
                param(
                    $ServerConnection
                )

                if ($ServerConnection.SqlConnectionObject) {
                    $sqlConnectionObject = $ServerConnection.SqlConnectionObject
                } else {
                    $sqlConnectionObject = [PSCustomObject]@{
                        ConnectionString = $ServerConnection.ConnectionString
                    }
                }
                $connectionContext = [PSCustomObject]@{
                    ConnectionString    = $sqlConnectionObject.ConnectionString
                    SqlConnectionObject = $sqlConnectionObject
                    StatementTimeout    = 0
                }

                Add-Member -InputObject $connectionContext -Name ExecuteWithResults -MemberType ScriptMethod -Value {
                    param($Query)
                } -Force

                [PSCustomObject]@{
                    ConnectionContext = $connectionContext
                }
            }

            Mock Add-ConnectionHashValue { } -ModuleName dbatools
            Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters } -ModuleName dbatools
            Mock New-Object {
                $sqlConnectionObject = if ($ArgumentList[0] -is [Microsoft.Data.SqlClient.SqlConnection]) {
                    $ArgumentList[0]
                } else {
                    $null
                }
                $script:lastServerConnection = [PSCustomObject]@{
                    ConnectionString      = $ArgumentList[0].ConnectionString
                    SqlConnectionObject   = $sqlConnectionObject
                    ConnectAsUser         = $false
                    ConnectAsUserName     = $null
                    ConnectAsUserPassword = $null
                }
                $script:lastServerConnection
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Common.ServerConnection"
            }
            Mock New-Object {
                New-MockAuthenticationServer -ServerConnection $ArgumentList[0]
            } -ModuleName dbatools -ParameterFilter {
                $TypeName -eq "Microsoft.SqlServer.Management.Smo.Server"
            }
        }

        It "requires SqlCredential when AuthenticationType uses password-based auth" {
            Mock Stop-Function { } -ModuleName dbatools

            Connect-DbaInstance -SqlInstance "sqlauth" -AuthenticationType ActiveDirectoryPassword | Should -BeNullOrEmpty

            Should -Invoke Stop-Function -Times 1 -Exactly -ModuleName dbatools
        }

        It "uses SqlConnectionInfo credentials for ActiveDirectoryPassword on non-Azure servers" {
            $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ("user@contoso.com", $securePassword)

            $result = Connect-DbaInstance -SqlInstance "sqlauth" -SqlCredential $credential -AuthenticationType ActiveDirectoryPassword -SqlConnectionOnly

            $result.ConnectionString | Should -Match "Authentication=ActiveDirectoryPassword"
            $result.ConnectionString | Should -Match "User ID=user@contoso.com"
            $result.ConnectionString | Should -Not -Match "Integrated Security=True"
            $script:lastServerConnection.ConnectAsUser | Should -Be $false
            $script:lastServerConnection.ConnectAsUserName | Should -BeNullOrEmpty
        }

        It "uses the SqlClient SSPI provider for explicit Windows credentials" -Skip:(-not $script:hasCredentialSspiProvider) {
            $splatPassword = @{
                String      = "password"
                AsPlainText = $true
                Force       = $true
            }
            $securePassword = ConvertTo-SecureString @splatPassword
            $credential = New-Object System.Management.Automation.PSCredential ("CONTOSO\user", $securePassword)
            $splatConnect = @{
                SqlInstance       = "sqlauth"
                SqlCredential     = $credential
                SqlConnectionOnly = $true
            }

            $result = Connect-DbaInstance @splatConnect

            $result.SspiContextProvider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
            $script:lastServerConnection.ConnectAsUser | Should -Be $false
            $script:lastServerConnection.ConnectAsUserName | Should -BeNullOrEmpty
            Should -Invoke Add-ConnectionHashValue -Times 0 -Exactly -ModuleName dbatools
        }

        It "uses SMO impersonation when the SqlClient SSPI provider is unavailable" -Skip:$script:hasCredentialSspiProvider {
            $splatPassword = @{
                String      = "password"
                AsPlainText = $true
                Force       = $true
            }
            $securePassword = ConvertTo-SecureString @splatPassword
            $credential = New-Object System.Management.Automation.PSCredential ("user@CONTOSO", $securePassword)
            $splatConnect = @{
                SqlInstance       = "sqlauth"
                SqlCredential     = $credential
                SqlConnectionOnly = $true
            }

            $null = Connect-DbaInstance @splatConnect

            $script:lastServerConnection.ConnectAsUser | Should -Be $true
            $script:lastServerConnection.ConnectAsUserName | Should -Be "user@CONTOSO"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
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

    Context "IsNewConnectionVariable tells the caller whether a connection was opened" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We predefine the variables so that a test fails if Connect-DbaInstance does not set them at all.
            $newFromString = $null
            $newFromServer = $null
            $newFromCopy = $null

            $serverFromString = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection -IsNewConnectionReference ([ref]$newFromString)
            $serverFromServer = Connect-DbaInstance -SqlInstance $serverFromString -IsNewConnectionReference ([ref]$newFromServer)
            # Asking for a different database forces Connect-DbaInstance to copy the connection context, so this is a new connection.
            $serverFromCopy = Connect-DbaInstance -SqlInstance $serverFromString -Database tempdb -IsNewConnectionReference ([ref]$newFromCopy)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = $serverFromString, $serverFromCopy | Disconnect-DbaInstance
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "is true when the connection is opened from a string" {
            $newFromString | Should -BeTrue
        }

        It "is false when the server object is passed back in" {
            $newFromServer | Should -BeFalse
        }

        It "returns the object that was passed in when nothing has to change" {
            [object]::ReferenceEquals($serverFromServer, $serverFromString) | Should -BeTrue
        }

        It "is true when the connection context has to be copied" {
            $newFromCopy | Should -BeTrue
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

    Context "connection is properly cloned from a connection that was created from a SqlConnection" {
        BeforeAll {
            # A ServerConnection that was built from a SqlConnection has its connection string set, and
            # SMO then refuses assignments to DatabaseName, NonPooledConnection and ServerInstance, so
            # cloning such a server has to go through the connection string instead. CI never noticed
            # because it covers SqlConnection to Server and Server to another Database, but never the
            # two of them chained. See #10584.
            [Microsoft.Data.SqlClient.SqlConnection]$sqlConnectionToClone = "Data Source=$($TestConfig.InstanceMulti1);Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
            $serverFromSqlConnection = Connect-DbaInstance -SqlInstance $sqlConnectionToClone
        }

        AfterAll {
            $null = $serverFromSqlConnection | Disconnect-DbaInstance
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlConnection -Database tempdb
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            $serverFromSqlConnection.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using parameter Database together with NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlConnection -Database tempdb -NonPooledConnection
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            $serverClone.ConnectionContext.ConnectionString | Should -Match "Pooling=False"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using parameter ApplicationIntent" {
            # ApplicationIntent is not one of the properties SMO refuses to assign, so this used to look
            # like it worked: the property took the value and read it back. On a fixed connection string
            # the assignment never reaches the string, and the string is what the login is made with -
            # SQL Server reads the intent at login time and routes on it then. So the context reported
            # ReadOnly over a connection that had logged in as ReadWrite, and with no other setting to
            # apply, nothing rebuilt the string to correct it.
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlConnection -ApplicationIntent ReadOnly
            $cloneStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $serverClone.ConnectionContext.ConnectionString
            $cloneStringBuilder["ApplicationIntent"] | Should -Be "ReadOnly"
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using parameter Database together with ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlConnection -Database tempdb -ApplicationIntent ReadOnly
            $cloneStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $serverClone.ConnectionContext.ConnectionString
            $cloneStringBuilder["ApplicationIntent"] | Should -Be "ReadOnly"
            $cloneStringBuilder["Initial Catalog"] | Should -Be "tempdb"
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using parameter DedicatedAdminConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlConnection -DedicatedAdminConnection
            $serverClone.ConnectionContext.ConnectionString | Should -Match "ADMIN:"
            # The connection context cannot be asked here, because ServerInstance is one of the properties
            # that cannot be assigned on such a context, so ask the session which endpoint it is on.
            $dacQuery = "SELECT COUNT(*) FROM sys.dm_exec_sessions AS s JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1 AND s.session_id = @@SPID"
            $serverClone.ConnectionContext.ExecuteScalar($dacQuery) | Should -Be 1
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "keeps the forced certificate trust of a local dedicated admin connection" -Skip:(-not $script:instanceIsLocalHost) {
            # A local DAC goes to ADMIN:localhost and forces TrustServerCertificate, because the
            # certificate of the instance does not have to match "localhost" (#10254). On a context whose
            # connection string is fixed, assigning that property succeeds and reads back as True while
            # the string still says False - and the string is what the new connection is built from. So
            # the trust has to be put into the string as well, or the local DAC fails on the certificate.
            # Starts from Trust Server Certificate=False on purpose: with True the assertion would pass
            # even if the command did nothing at all.
            $localDacConnectionString = "Data Source=$($TestConfig.InstanceMulti1);Integrated Security=True;Encrypt=False;Trust Server Certificate=False"
            [Microsoft.Data.SqlClient.SqlConnection]$localDacConnection = $localDacConnectionString
            $serverForLocalDac = Connect-DbaInstance -SqlInstance $localDacConnection
            try {
                $serverClone = Connect-DbaInstance -SqlInstance $serverForLocalDac -DedicatedAdminConnection

                # Read back through a builder rather than matching the string: a connection string builder
                # keeps the spelling it was given, so the same setting reads as "Trust Server Certificate"
                # or "TrustServerCertificate" depending on how the caller wrote it.
                $cloneStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $serverClone.ConnectionContext.ConnectionString
                $cloneStringBuilder["Trust Server Certificate"] | Should -BeTrue
                $cloneStringBuilder["Data Source"] | Should -Match "^ADMIN:localhost"
                $null = $serverClone | Disconnect-DbaInstance
            } finally {
                $null = $serverForLocalDac | Disconnect-DbaInstance
            }
        }
    }

    Context "connection is properly cloned from an open SQL authenticated SqlConnection" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Once a SqlConnection has been opened with Persist Security Info=False, SqlClient hides the
            # password: the connection string that can be read back no longer carries one. Anything that
            # rebuilds the connection string from it therefore produces a connection that cannot log in,
            # so the database has to be switched on the connection that already exists. See #10584.
            $sqlAuthLogin = "dbatoolsci_clone_$(Get-Random)"
            $sqlAuthPassword = "dbatools.IO_$(Get-Random)"
            $splatSqlAuthLogin = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Login       = $sqlAuthLogin
                Password    = (ConvertTo-SecureString -String $sqlAuthPassword -AsPlainText -Force)
                Force       = $true
            }
            $null = New-DbaLogin @splatSqlAuthLogin
            $null = Set-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $sqlAuthLogin -AddRole sysadmin

            $sqlAuthConnectionString = "Data Source=$($TestConfig.InstanceMulti1);Initial Catalog=master;User ID=$sqlAuthLogin;Password=$sqlAuthPassword;Persist Security Info=False;Encrypt=False;Trust Server Certificate=True"
            $sqlAuthConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $sqlAuthConnectionString
            $sqlAuthConnection.Open()
            $serverFromSqlAuth = Connect-DbaInstance -SqlInstance $sqlAuthConnection

            # The session counting of the tests below goes through a connection of its own, opened once
            # here. Passing an instance name to Get-DbaProcess instead would open a new connection on
            # every call, and each of those registers itself with the tab expansion cache under the same
            # instance key - which drops the reference to whatever was stored there before, and with it
            # the leaked connection these tests are looking for. Counting would then hide the growth it
            # is supposed to prove.
            $serverForCounting = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $serverFromSqlAuth, $serverForCounting | Disconnect-DbaInstance
            $sqlAuthConnection.Close()
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $sqlAuthLogin -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "hides the password from the connection string, which is what makes this case hard" {
            $serverFromSqlAuth.ConnectionContext.ConnectionString | Should -Not -Match "Password="
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlAuth -Database tempdb
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            $serverClone.ConnectionContext.ExecuteScalar("select suser_sname()") | Should -Be $sqlAuthLogin
            $serverFromSqlAuth.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "refuses instead of returning a server that cannot log in" {
            # This one needs a new connection, and the password for it is gone, so the command has to say
            # so rather than hand back something that fails on first use. Connect-DbaInstance throws by
            # default, which is why this is not a warning.
            { Connect-DbaInstance -SqlInstance $serverFromSqlAuth -Database tempdb -NonPooledConnection } |
                Should -Throw -ExpectedMessage "*cannot be reproduced from its connection string*"
        }

        It "keeps the session count flat over repeated refusals" {
            # A refusal happens after the connection context has been copied, and Copy() clones an open
            # connection as an open connection. Nothing but the returned server object can ever close that
            # copy, so a refusal that simply returns leaves a session behind that nothing can reuse - the
            # same orphaned connection this whole change is about, only on the failure path. Repeated on
            # purpose: one sleeping pooled session is legitimate, growth is not.
            $countPerCycle = @()
            foreach ($cycle in 1..5) {
                { Connect-DbaInstance -SqlInstance $serverFromSqlAuth -Database tempdb -NonPooledConnection } | Should -Throw
                $countPerCycle += @(Get-DbaProcess -SqlInstance $serverForCounting -Login $sqlAuthLogin).Count
            }
            ($countPerCycle | Select-Object -Unique).Count | Should -Be 1
        }

        It "keeps the session count flat over repeated failed database switches" {
            # The other way out of the same block: the copy exists and is open, and switching it to a
            # database that does not exist throws from inside SMO rather than through Stop-Function.
            $countPerCycle = @()
            foreach ($cycle in 1..5) {
                { Connect-DbaInstance -SqlInstance $serverFromSqlAuth -Database "dbatoolsci_does_not_exist_$cycle" } | Should -Throw
                $countPerCycle += @(Get-DbaProcess -SqlInstance $serverForCounting -Login $sqlAuthLogin).Count
            }
            ($countPerCycle | Select-Object -Unique).Count | Should -Be 1
        }

        It "keeps the session count flat over repeated successful clones" {
            # And the path that succeeds. This one switches the database on the connection the copy holds,
            # which leaves that connection open, and an open connection was then copied a second time for
            # the tab expansion cache and kept there for the life of the process. That copy was reachable
            # by nothing, so every call parked another session: the count went 3, 4, 5, 6, 7, 8.
            $countPerCycle = @()
            foreach ($cycle in 1..5) {
                $serverClone = Connect-DbaInstance -SqlInstance $serverFromSqlAuth -Database tempdb
                $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
                $null = $serverClone | Disconnect-DbaInstance
                $countPerCycle += @(Get-DbaProcess -SqlInstance $serverForCounting -Login $sqlAuthLogin).Count
            }
            ($countPerCycle | Select-Object -Unique).Count | Should -Be 1
        }
    }

    Context "connection is properly cloned on Azure SQL Database" -Skip:(-not $script:hasAzureSqlDb) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Azure SQL Database answers a USE with error 40508 and wants a new connection for another
            # database. Every other engine, Azure SQL Managed Instance included, takes the USE, so the
            # branch that switches the database on an existing connection looks correct everywhere else
            # and is wrong only here. See #10584.
            # A serverless database that has been idle is paused and takes up to a minute to wake up. A
            # generous ConnectTimeout does not cover that: while the database resumes, Azure does not
            # keep the attempt waiting, it answers it right away with error 40613 "Database ... is not
            # currently available. Please retry the connection later." So the first connection is
            # retried until the database is up, and only an error that says something else is thrown
            # immediately.
            $splatAzureConnect = @{
                SqlInstance    = $TestConfig.AzureSqlDbServer
                Database       = $TestConfig.AzureSqlDbName
                SqlCredential  = $TestConfig.AzureSqlDbCred
                ConnectTimeout = 120
            }
            $azureResumeAttempt = 0
            while ($null -eq $serverAzure) {
                $azureResumeAttempt++
                try {
                    $serverAzure = Connect-DbaInstance @splatAzureConnect
                } catch {
                    if ($azureResumeAttempt -ge 10 -or $PSItem.Exception.Message -notmatch "is not currently available") {
                        throw
                    }
                    Start-Sleep -Seconds 15
                }
            }

            # The same login again, but through a SqlConnection, which gives the server a fixed connection
            # string and so takes the code path that cannot assign DatabaseName. Persist Security Info is
            # on, so the password survives being read back and a new connection can be built from it.
            $azurePassword = $TestConfig.AzureSqlDbCred.GetNetworkCredential().Password
            $azureConnectionString = @(
                "Data Source=$($TestConfig.AzureSqlDbServer)"
                "Initial Catalog=$($TestConfig.AzureSqlDbName)"
                "User ID=$($TestConfig.AzureSqlDbCred.UserName)"
                "Password=$azurePassword"
                "Encrypt=True"
                "Persist Security Info=True"
                "Connect Timeout=120"
            ) -join ";"
            $azureConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $azureConnectionString
            $azureConnection.Open()
            $serverAzureFromSqlConnection = Connect-DbaInstance -SqlInstance $azureConnection

            # And once more with the password hidden, which is what an opened connection looks like by
            # default. Nothing can rebuild a connection string from this one.
            $azureHiddenConnectionString = $azureConnectionString -replace "Persist Security Info=True", "Persist Security Info=False"
            $azureHiddenConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $azureHiddenConnectionString
            $azureHiddenConnection.Open()
            $serverAzureHiddenPassword = Connect-DbaInstance -SqlInstance $azureHiddenConnection

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The BeforeAll can fail partway through - an Azure SQL Database that stays unavailable is the
            # realistic case - and then the variables below it were never assigned. Calling a method on
            # one of them throws from the teardown, and Pester reports that null reference on every test
            # of the block instead of the error that really happened.
            $null = $serverAzure, $serverAzureFromSqlConnection, $serverAzureHiddenPassword | Where-Object { $null -ne $PSItem } | Disconnect-DbaInstance
            if ($azureConnection) {
                $azureConnection.Close()
            }
            if ($azureHiddenConnection) {
                $azureHiddenConnection.Close()
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "really is an Azure SQL Database, which is what makes this case different" {
            # Guards the three tests below: against anything else they would pass without proving
            # anything, because every other engine simply takes the USE.
            $serverAzure.DatabaseEngineEdition | Should -Be "SqlDatabase"
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $serverAzure -Database master
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $serverAzure.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be $TestConfig.AzureSqlDbName
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using parameter Database from a server that was created from a SqlConnection" {
            # The regression: a fixed connection string cannot take DatabaseName, and switching the
            # database on the connection instead is exactly what Azure SQL Database refuses. The database
            # has to go into the connection string as Initial Catalog, which is also the only thing that
            # gives it the right connection pool.
            $serverClone = Connect-DbaInstance -SqlInstance $serverAzureFromSqlConnection -Database master
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $serverClone.ConnectionContext.ExecuteScalar("select suser_sname()") | Should -Be $TestConfig.AzureSqlDbCred.UserName
            $serverAzureFromSqlConnection.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be $TestConfig.AzureSqlDbName
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "refuses rather than trying to switch the database on the connection" {
            # No new connection can be built here, because the password is gone, and the fallback that
            # every other engine uses cannot work on Azure SQL Database. The command has to say so. The
            # last assertion is the one with teeth: it fails if the code ever reaches ChangeDatabase,
            # which answers with "USE statement is not supported to switch between databases".
            $errorRecord = $null
            try {
                $null = Connect-DbaInstance -SqlInstance $serverAzureHiddenPassword -Database master
            } catch {
                $errorRecord = $PSItem
            }
            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.Exception.Message | Should -BeLike "*Azure SQL Database does not support switching the database*"
            $errorRecord.Exception.Message | Should -Not -BeLike "*USE statement is not supported*"
        }
    }

    Context "connection is properly cloned from an existing connection" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        }

        AfterAll {
            $null = $server | Disconnect-DbaInstance
        }

        It "clones when using parameter Database" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "master"
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
        }

        It "hands the clone a connection that Disconnect-DbaInstance can close" {
            # The clone used to be built with GetDatabaseConnection, which opened the connection on an
            # intermediate copy and returned a different context. The clone therefore did not own its
            # connection and Disconnect-DbaInstance closed nothing, so every call left a session parked
            # in the database holding a shared lock on it.
            # Repeated on purpose. With pooling, a sleeping session that stays behind is legitimate - it
            # belongs to the pool and the next call reuses it. What must not happen is that their number
            # grows with every call, which is what an orphaned connection looks like: nothing can reuse
            # it and nothing can close it. Against the old implementation the count went up on almost
            # every cycle, so a single cycle is not enough to tell the two apart.
            $countPerCycle = @()
            foreach ($cycle in 1..5) {
                $serverParked = Connect-DbaInstance -SqlInstance $server -Database tempdb
                $serverParked.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
                $null = $serverParked | Disconnect-DbaInstance
                $countPerCycle += @(Get-DbaProcess -SqlInstance $server -Database tempdb | Where-Object Program -match "dbatools").Count
            }

            # Every cycle has to land on the same number, not just the first and the last. A sequence like
            # 4, 5, 4, 5, 4 starts and ends the same way and still means the pool is churning.
            ($countPerCycle | Select-Object -Unique).Count | Should -Be 1
        }

        It "clones when using parameter ApplicationIntent" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -ApplicationIntent ReadOnly
            $server.ConnectionContext.ApplicationIntent | Should -BeNullOrEmpty
            $serverClone.ConnectionContext.ApplicationIntent | Should -Be "ReadOnly"
        }

        It "clones when using parameter Database together with NonPooledConnection" {
            $serverClone = Connect-DbaInstance -SqlInstance $server -Database tempdb -NonPooledConnection
            $serverClone.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be "tempdb"
            $serverClone.ConnectionContext.NonPooledConnection | Should -Be $true
            $null = $serverClone | Disconnect-DbaInstance
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
            $null = $serverClone | Disconnect-DbaInstance
        }

        It "clones when using Backup-DabInstace" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            # The backups have to go to the shared temp folder. Without a path they land in the default
            # backup folder of the instance, which is a path on the SQL Server, so the Remove-Item below
            # runs against a path that does not exist on the machine running the tests and silently does
            # nothing. The backup was then left behind on every remote instance, and because this file
            # runs early in the suite, every later test file reported it as a leftover of its own.
            # Each backup gets its own file name, because two backups within the same minute share the
            # default name and the second one appends to the first.
            $backupFiles = @()
            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb -Path $TestConfig.Temp -FilePath "msdb_$(Get-Random).bak"
            if ($results.FullName) {
                $backupFiles += $results.FullName
            }

            $results = Backup-DbaDatabase -SqlInstance $server -Database msdb -Path $TestConfig.Temp -FilePath "msdb_$(Get-Random).bak" -WarningVariable warn
            $warn | Should -BeNullOrEmpty

            if ($results.FullName) {
                $backupFiles += $results.FullName
            }

            # Right after the backup the share can still hold the file open for a moment, and a silently
            # failed removal left it behind once. Retry a few times and then insist that it is gone.
            foreach ($backupFile in $backupFiles) {
                $attempts = 0
                while ((Test-Path -Path $backupFile) -and $attempts -lt 5) {
                    $attempts++
                    Remove-Item -Path $backupFile -ErrorAction SilentlyContinue
                    if (Test-Path -Path $backupFile) {
                        Start-Sleep -Seconds 1
                    }
                }
                Test-Path -Path $backupFile | Should -BeFalse
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
        It "opens and closes the connections" {
            $instance1 = [DbaInstanceParameter]$TestConfig.InstanceMulti1
            if ($instance1.IsLocalHost) {
                if ($instance1.InstanceName -ne 'MSSQLSERVER') {
                    $name1 = "ADMIN:localhost\$($instance1.InstanceName)"
                } else {
                    $name1 = "ADMIN:localhost"
                }
            } else {
                $name1 = 'ADMIN:' + $instance1.FullName
            }
            $instance2 = [DbaInstanceParameter]$TestConfig.InstanceMulti2
            if ($instance2.IsLocalHost) {
                if ($instance2.InstanceName -ne 'MSSQLSERVER') {
                    $name2 = "ADMIN:localhost\$($instance2.InstanceName)"
                } else {
                    $name2 = "ADMIN:localhost"
                }
            } else {
                $name2 = 'ADMIN:' + $instance2.FullName
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server[0].Name | Should -Be $name1
            $server[1].Name | Should -Be $name2
            $null = $server | Disconnect-DbaInstance
            # DAC is not reopened in the background
            Start-Sleep -Seconds 10
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -DedicatedAdminConnection
            $server.Count | Should -Be 2
            $null = $server | Disconnect-DbaInstance
        }
    }

    Context "MinimumVersion decides based on a version it can read" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $versionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $smoVersionMajor = $versionServer.VersionMajor
            $connectionVersionMajor = $versionServer.ConnectionContext.ServerVersion.Major
            $productVersionQuery = @"
SELECT SERVERPROPERTY('ProductVersion')
"@
            $tsqlVersionMajor = [int](($versionServer.ConnectionContext.ExecuteScalar($productVersionQuery) -split "\.")[0])

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns the connection when the instance meets the minimum" {
            $result = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -MinimumVersion $smoVersionMajor
            $result.VersionMajor | Should -Be $smoVersionMajor
        }

        It "refuses the connection when the instance is below the minimum" {
            { Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -MinimumVersion ($smoVersionMajor + 1) } | Should -Throw "*SQL Server version $($smoVersionMajor + 1) required*"
        }

        It "warns instead of throwing when exceptions are disabled" {
            $splatTooNew = @{
                SqlInstance      = $TestConfig.InstanceMulti1
                MinimumVersion   = $smoVersionMajor + 1
                DisableException = $true
                WarningVariable  = "minimumVersionWarning"
                WarningAction    = "SilentlyContinue"
            }
            $result = Connect-DbaInstance @splatTooNew
            $result | Should -BeNullOrEmpty
            $minimumVersionWarning | Should -Match "SQL Server version $($smoVersionMajor + 1) required"
        }

        It "can read the same major version from the connection as from SMO" {
            # The check falls back to ConnectionContext.ServerVersion where SMO cannot serve
            # VersionMajor, which is every instance below SQL Server 2008. No instance in the
            # matrix is that old, so this guards the fallback source instead: if it ever stops
            # agreeing with SMO, the fallback stops refusing the versions it exists to refuse.
            $connectionVersionMajor | Should -Be $smoVersionMajor
        }

        It "can read the same major version from T-SQL as from SMO" {
            # The last fallback, and the only one proven to answer on SQL Server 2005, where both
            # properties above come back empty. Guarded here for the same reason: the versions it
            # exists to refuse are not in the matrix, but its source is readable everywhere.
            $tsqlVersionMajor | Should -Be $smoVersionMajor
        }
    }
}
