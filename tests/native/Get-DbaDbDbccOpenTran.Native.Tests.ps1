#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbDbccOpenTran",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; DBCC OPENTRAN only reports the oldest active transaction.

Describe "Get-DbaDbDbccOpenTran native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run (lane-safe); AfterAll drops the databases.
        $prefix = "native_opentran_" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $quietName = "${prefix}_quiet"
        $busyName = "${prefix}_busy"
        $quietDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $quietName
        $quietDatabase.Create()
        $busyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $busyName
        $busyDatabase.Create()
        $busyDatabase.ExecuteNonQuery("CREATE TABLE dbo.native_opentran (id int NOT NULL);")
        $badInstance = "TCP:127.0.0.1,1"
        $propertyNames = @("ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseId", "Cmd", "Output", "Field", "Data")
    }

    AfterAll {
        # KillDatabase ends the command's pooled connections before the drop.
        $server.Databases.Refresh()
        foreach ($dbName in @($quietName, $busyName)) {
            if ($server.Databases[$dbName]) {
                $server.KillDatabase($dbName)
            }
        }
    }

    Context "Results" {
        It "returns the pinned row for a database with no open transaction" {
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $quietName -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            $result.PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            @($result.PSObject.Properties.Name) | Should -Be $propertyNames
            $result.ComputerName | Should -BeExactly $server.ComputerName
            $result.InstanceName | Should -BeExactly $server.ServiceName
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.Database | Should -BeExactly $quietName
            $result.DatabaseId | Should -Be $quietDatabase.ID
            $result.Cmd | Should -BeExactly "DBCC OPENTRAN('$quietName') WITH TABLERESULTS, NO_INFOMSGS"
            $result.Output | Should -BeExactly "No active open transactions."
            $result.Field | Should -BeNullOrEmpty
            $result.Data | Should -BeNullOrEmpty
        }

        It "reports an open transaction field by field" {
            $splatOpenConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $busyName
                NonPooledConnection = $true
                EnableException     = $true
            }
            $openServer = Connect-DbaInstance @splatOpenConnection
            try {
                $openSession = $openServer.ConnectionContext.ExecuteScalar("SELECT @@SPID;")
                $null = $openServer.ConnectionContext.ExecuteNonQuery("BEGIN TRANSACTION; INSERT INTO dbo.native_opentran (id) VALUES (1);")
                $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $busyName -EnableException)
                $results.Count | Should -BeGreaterThan 0
                foreach ($result in $results) {
                    $result.Database | Should -BeExactly $busyName
                    $result.Output | Should -BeExactly "Oldest active transaction"
                    $result.Field | Should -Not -BeNullOrEmpty
                    $result.Cmd | Should -BeExactly "DBCC OPENTRAN('$busyName') WITH TABLERESULTS, NO_INFOMSGS"
                }
                # One of the rows names the session that holds the transaction; DBCC reports the fields as sql_variant values.
                @($results | Where-Object { ($PSItem.Data -as [int]) -eq [int]$openSession }).Count | Should -BeGreaterThan 0
            } finally {
                $null = $openServer.ConnectionContext.ExecuteNonQuery("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
                $openServer.ConnectionContext.Disconnect()
            }
        }

        # The pinned $query.Replace('#options#', "'$($db.Name)'") puts the name into the batch as it is, so this name ends the
        # literal and runs its own statement. Doubling the quote keeps the whole name inside the literal.
        It "keeps a quote in a database name inside the literal" {
            $quotedName = "${prefix}'); SELECT 1; --"
            $quotedDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $quotedName
            $quotedDatabase.Create()
            try {
                $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $quotedName -EnableException)
                $results.Count | Should -Be 1
                $results[0].Database | Should -BeExactly $quotedName
                $results[0].Output | Should -BeExactly "No active open transactions."
                $results[0].Cmd | Should -BeExactly ("DBCC OPENTRAN('" + $quotedName.Replace("'", "''") + "') WITH TABLERESULTS, NO_INFOMSGS")
            } finally {
                $server.Databases.Refresh()
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$quotedName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$quotedName];")
            }
        }
    }

    Context "The -Database filter" {
        It "selects by name, ignoring case" {
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $quietName.ToUpperInvariant() -EnableException)
            $results.Database | Should -BeExactly $quietName
        }

        It "selects by id, as the help documents" {
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database "$($quietDatabase.ID)" -EnableException)
            $results.Database | Should -BeExactly $quietName
        }

        # $_.ID -In $Database compares with each value as the left operand, so a string value compares as a string.
        It "compares an id with each value as text, as -In does" {
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database "0$($quietDatabase.ID)" -EnableException)
            $results.Count | Should -Be 0
        }

        It "selects nothing for an empty bound -Database, as Test-Bound does" {
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database @() -EnableException)
            $results.Count | Should -Be 0
        }
    }

    Context "A database that is not accessible" {
        It "warns and goes on to the next database, and stops there under -EnableException" {
            $offlineName = "${prefix}_offline"
            $offlineDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $offlineName
            $offlineDatabase.Create()
            try {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
                $offlineWarnings = @()
                $results = @(Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $quietName -WarningVariable offlineWarnings -WarningAction SilentlyContinue)
                $results.Database | Should -BeExactly $quietName
                ($offlineWarnings -join " ") | Should -Match ([regex]::Escape("The database [$offlineName] is not accessible. Skipping."))

                $offlineCaught = $null
                try {
                    $null = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database $offlineName -EnableException
                } catch {
                    $offlineCaught = $PSItem
                }
                $offlineCaught.Exception.Message | Should -BeExactly "The database [$offlineName] is not accessible. Skipping."
            } finally {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET ONLINE;")
                $server.Databases.Refresh()
                $server.KillDatabase($offlineName)
            }
        }
    }

    Context "A DBCC command the login may not run" {
        BeforeAll {
            # DBCC OPENTRAN needs sysadmin or db_owner (Microsoft Learn), which this user lacks.
            $deniedUser = "${prefix}_denied"
            $quietDatabase.ExecuteNonQuery("CREATE USER [$deniedUser] WITHOUT LOGIN;")
            $splatDeniedConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $quietName
                NonPooledConnection = $true
                EnableException     = $true
            }
            $deniedServer = Connect-DbaInstance @splatDeniedConnection
            # Read while still sysadmin: the impersonated user cannot see the other databases.
            foreach ($deniedDatabase in $deniedServer.Databases) {
                $null = $deniedDatabase.ID
                $null = $deniedDatabase.IsAccessible
            }
            $null = $deniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$deniedUser';")
            $deniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedUser
        }

        AfterAll {
            if ($deniedServer) {
                $deniedServer.ConnectionContext.Disconnect()
            }
        }

        It "warns 'Error capturing data' and writes no row" {
            $deniedWarnings = @()
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $deniedServer -Database $quietName -WarningVariable deniedWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($deniedWarnings -join " ") | Should -Match ([regex]::Escape("Error capturing data on [$quietName]"))
        }

        It "throws the Query method's failure under -EnableException, as the pinned -Exception `$_.Exception does" {
            $deniedCaught = $null
            try {
                $null = Get-DbaDbDbccOpenTran -SqlInstance $deniedServer -Database $quietName -EnableException
            } catch {
                $deniedCaught = $PSItem
            }
            $deniedCaught | Should -Not -BeNullOrEmpty
            $deniedCaught.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
            $deniedCaught.Exception.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s):*'
        }
    }

    Context "Several instances" {
        It "queries every piped instance" -Tag NativeChecklist:pipeline-multiple {
            $results = @(@($TestConfig.InstanceSingle, $TestConfig.InstanceSingle) | Get-DbaDbDbccOpenTran -Database $quietName -EnableException)
            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Database | Should -BeExactly $quietName
            }
        }

        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $quietName -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            ($connectWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Database | Should -BeExactly $quietName
        }

        It "stops at the instance it cannot connect to under -EnableException, with category ConnectionError" -Tag NativeChecklist:enable-exception {
            $seen = New-Object System.Collections.ArrayList
            $connectCaught = $null
            try {
                Get-DbaDbDbccOpenTran -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $quietName -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $connectCaught = $PSItem
            }
            $connectCaught | Should -Not -BeNullOrEmpty
            $connectCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbDbccOpenTran*"
            $connectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $seen.Count | Should -Be 0
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $quietName -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Database | Should -BeExactly $quietName
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run (watchman
        # 49f13ebb): no commit can run the pinned function, because the base already ships a compiled cmdlet.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbDbccOpenTran.ps1, the process block:
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on; under
        # -EnableException the same Stop-Function throws with category ConnectionError.
        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Count | Should -BeGreaterThan 0
            $results[0].Database | Should -BeExactly "master"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaDbDbccOpenTran -SqlInstance $loginInstance -Database master -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $noLoginCaught = $null
            try {
                $null = Get-DbaDbDbccOpenTran -SqlInstance $loginInstance -Database master -EnableException
            } catch {
                $noLoginCaught = $PSItem
            }
            $noLoginCaught | Should -Not -BeNullOrEmpty
            $noLoginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaDbDbccOpenTran on Azure SQL Database" -Tag IntegrationTests {
    # DBCC OPENTRAN applies to Azure SQL Database (Microsoft Learn).
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureCommand = "DBCC OPENTRAN('$($TestConfig.AzureSqlDbName)') WITH TABLERESULTS, NO_INFOMSGS"
    }

    It "reads the database a connection is in" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $splatAzureOpenTran = @{
            SqlInstance     = $azureServer
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbDbccOpenTran @splatAzureOpenTran)
        $azureRows.Count | Should -BeGreaterThan 0
        foreach ($azureRow in $azureRows) {
            $azureRow.Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRow.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $azureRow.Cmd | Should -BeExactly $azureCommand
            $azureRow.Output | Should -BeIn @("No active open transactions.", "Oldest active transaction")
        }
    }

    # Without -Database the connection lands in the logical server's master, and an Azure SQL database can only be asked
    # about itself from its own connection.
    It "reads a database from a connection to the logical server" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureServerLevel = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            SqlCredential   = $TestConfig.AzureSqlDbCred
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbDbccOpenTran @splatAzureServerLevel)
        $azureRows.Count | Should -BeGreaterThan 0
        foreach ($azureRow in $azureRows) {
            $azureRow.Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRow.Cmd | Should -BeExactly $azureCommand
            $azureRow.Output | Should -BeIn @("No active open transactions.", "Oldest active transaction")
        }
    }
}
