$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ApplicationIntent', 'AzureUnsupported', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'FailoverPartner', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'MinimumVersion', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AppendConnectionString', 'SqlConnectionOnly', 'AzureDomain', 'AuthenticationType', 'Tenant', 'Thumbprint', 'Store', 'AccessToken', 'DedicatedAdminConnection', 'DisableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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
            $server.ConnectionContext.ConnectionString -match "Intent=ReadOnly" | Should Be $true
        }

        It "sets StatementTimeout to 0" {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 -StatementTimeout 0

            $server.ConnectionContext.StatementTimeout | Should Be 0
        }

        It "connects using a connection string" {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$script:instance1;Initial Catalog=tempdb;Integrated Security=True;"
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "connects using a connection object" {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$script:instance1;Initial Catalog=tempdb;Integrated Security=True;"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            $server.ComputerName | Should Be ([DbaInstance]$script:instance1).ComputerName
            $server.Databases.Name.Count -gt 0 | Should Be $true
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
        }

        It "connects - instance2" {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "connects using a connection string - instance2" {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$script:instance2;Initial Catalog=tempdb;Integrated Security=True;"
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "connects using a connection object - instance2" {
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
            [Microsoft.Data.SqlClient.SqlConnection]$sqlconnection = "Data Source=$script:instance2;Initial Catalog=tempdb;Integrated Security=True;"
            $server = Connect-DbaInstance -SqlInstance $sqlconnection
            $server.ComputerName | Should Be ([DbaInstance]$script:instance2).ComputerName
            $server.Databases.Name.Count -gt 0 | Should Be $true
            Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value $null
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

Describe "$commandname Integration Tests (moved here from Connect-SqlInstance)" -Tags "IntegrationTests" {
    $password = 'MyV3ry$ecur3P@ssw0rd'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $server = Connect-DbaInstance -SqlInstance $script:instance1
    $login = "csitester"

    #Cleanup

    $results = Invoke-DbaQuery -SqlInstance $script:instance1 -Query "IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'"
    foreach ($spid in $results.spid) {
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query "kill $spid"
    }

    if ($l = $server.logins[$login]) {
        if ($c = $l.EnumCredentials()) {
            $l.DropCredential($c)
        }
        $l.Drop()
    }

    #Create login
    $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $login)
    $newLogin.LoginType = "SqlLogin"
    $newLogin.Create($password)

    Context "Connect with a new login" {
        It "Should login with newly created Sql Login (also tests credential login) and get instance name" {
            $cred = New-Object System.Management.Automation.PSCredential ($login, $securePassword)
            $s = Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $cred
            $s.Name | Should Be $script:instance1
        }
        It "Should return existing process running under the new login and kill it" {
            $results = Invoke-DbaQuery -SqlInstance $script:instance1 -Query "IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'"
            $results | Should Not BeNullOrEmpty
            foreach ($spid in $results.spid) {
                { Invoke-DbaQuery -SqlInstance $script:instance1 -Query "kill $spid" -ErrorAction Stop} | Should Not Throw
            }
        }
    }

    #Cleanup
    if ($l = $server.logins[$login]) {
        if ($c = $l.EnumCredentials()) {
            $l.DropCredential($c)
        }
        $l.Drop()
    }
}