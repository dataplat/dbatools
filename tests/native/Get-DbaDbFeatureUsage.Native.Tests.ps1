#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbFeatureUsage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads a dynamic management view.

Describe "Get-DbaDbFeatureUsage native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run (lane-safe); AfterAll drops all of it. The creation order differs from the name order, and
        # the output follows sys.databases, not the name-sorted SMO collection.
        $prefix = "native_feature_" + [Guid]::NewGuid().ToString("N")
        $dbFirst = "${prefix}_zz"
        $dbSecond = "${prefix}_aa"
        $dbPlain = "${prefix}_mm"
        $dbOffline = "${prefix}_off"
        $dbStale = "${prefix}_stale"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        foreach ($dbName in @($dbFirst, $dbSecond, $dbPlain, $dbOffline, $dbStale)) {
            $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbName
            $database.Create()
        }
        foreach ($dbName in @($dbFirst, $dbSecond)) {
            $server.Databases[$dbName].ExecuteNonQuery("CREATE TABLE dbo.TestCompression (Column1 nvarchar(10), Column2 int PRIMARY KEY); ALTER TABLE dbo.TestCompression REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);")
        }
        $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$dbOffline] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $badInstance = "TCP:127.0.0.1,1"
        $splatRead = @{
            SqlInstance     = $TestConfig.InstanceSingle
            EnableException = $true
        }
    }

    AfterAll {
        foreach ($dbName in @($dbOffline, $dbStale)) {
            $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$dbName] SET ONLINE;")
        }
        # KillDatabase ends the command's pooled connections before the drop.
        $server.Databases.Refresh()
        foreach ($dbName in @($dbFirst, $dbSecond, $dbPlain, $dbOffline, $dbStale)) {
            if ($server.Databases[$dbName]) {
                $server.KillDatabase($dbName)
            }
        }
    }

    Context "Rows" {
        It "returns the raw data rows with the query's six columns" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond)
            $rows.Count | Should -Be 1
            $rows[0] | Should -BeOfType System.Data.DataRow
            $rows[0].Table.Columns.ColumnName | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Id", "Feature", "Database")
            $rows[0].Feature | Should -BeExactly "Compression"
            $rows[0].Id | Should -BeOfType System.Int32
            $rows[0].Database | Should -BeExactly $dbSecond
        }

        It "reports the instance as the server does" {
            $expected = $server.ConnectionContext.ExecuteWithResults("SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance").Tables[0].Rows[0]
            $row = @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond)[0]
            $row.ComputerName | Should -BeExactly $expected.ComputerName
            $row.InstanceName | Should -BeExactly $expected.InstanceName
            $row.SqlInstance | Should -BeExactly $expected.SqlInstance
        }

        It "reports the feature's own id" {
            $expected = $server.Databases[$dbSecond].ExecuteWithResults("SELECT feature_id FROM sys.dm_db_persisted_sku_features").Tables[0].Rows[0].feature_id
            @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond)[0].Id | Should -Be $expected
        }

        # Measured on the pin, both editions: probes/pin-featureusage-20261101.ps1, cases shape and reversed-names.
        It "returns the rows in sys.databases order, not by name" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond, $dbFirst)
            $rows.Database | Should -BeExactly @($dbFirst, $dbSecond)
        }

        # Measured on the pin, both editions: cases plain-only and shape, no row and no null for such a database.
        It "returns nothing at all for a database with no such feature" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbPlain)
            $rows.Count | Should -Be 0
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbFirst, $dbPlain, $dbSecond)
            $rows.Count | Should -Be 2
        }

        It "writes the pinned verbose line for each database" {
            $verbose = @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Processing*" })
            $verbose.Count | Should -Be 1
            $verbose[0].Message | Should -BeLike "*Processing ``[$dbSecond``] on $($server.Name)"
        }

        It "does nothing and says nothing without an instance or a database" {
            $noWarnings = @()
            $results = @(Get-DbaDbFeatureUsage -WarningVariable noWarnings)
            $results.Count | Should -Be 0
            $noWarnings.Count | Should -Be 0
        }

        It "leaves the caller's connection in its database" {
            $context = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database $dbPlain -NonPooledConnection -EnableException
            try {
                $null = Get-DbaDbFeatureUsage -SqlInstance $context -Database $dbSecond -EnableException
                $context.ConnectionContext.CurrentDatabase | Should -BeExactly $dbPlain
            } finally {
                $context.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Choosing databases" {
        It "matches -Database ignoring case" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbSecond.ToUpperInvariant())
            $rows.Database | Should -BeExactly $dbSecond
        }

        # Two characters after the prefix: the _zz, _aa and _mm databases, not the offline one.
        It "honours a wildcard in -Database" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database "${prefix}_??")
            $rows.Database | Should -BeExactly @($dbFirst, $dbSecond)
        }

        It "honours a wildcard in -ExcludeDatabase" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbFirst, $dbSecond -ExcludeDatabase "*_aa")
            $rows.Database | Should -BeExactly $dbFirst
        }

        It "excludes a literal name" {
            $rows = @(Get-DbaDbFeatureUsage @splatRead -Database $dbFirst, $dbSecond -ExcludeDatabase $dbSecond)
            $rows.Database | Should -BeExactly $dbFirst
        }

        It "treats an empty -Database as no filter" {
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -Database "" -ExcludeDatabase $dbOffline, $dbStale -WarningAction SilentlyContinue)
            $rows.Database | Should -Contain $dbSecond
        }
    }

    Context "Databases from the pipeline" {
        BeforeAll {
            $pipedTwo = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbFirst, $dbSecond -EnableException
        }

        It "reads every piped database" -Tag NativeChecklist:pipeline-multiple {
            $rows = @($pipedTwo | Get-DbaDbFeatureUsage -EnableException)
            $rows.Database | Should -BeExactly @($dbFirst, $dbSecond)
        }

        It "reads a database array first, then the instance's databases" {
            $rows = @(Get-DbaDbFeatureUsage -InputObject $pipedTwo -SqlInstance $TestConfig.InstanceSingle -Database $dbSecond -EnableException)
            $rows.Database | Should -BeExactly @($dbFirst, $dbSecond, $dbSecond)
        }

        # The pin reads the instance again for each piped record, so these two repeat $dbSecond once more there: case
        # piped-with-instance, four rows on both editions.
        It "reads the instance's databases once when several databases are piped" {
            $rows = @($pipedTwo | Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbSecond -EnableException)
            $rows.Database | Should -BeExactly @($dbFirst, $dbSecond, $dbSecond)
        }
    }

    Context "Null input" {
        # Measured on the pin, both editions: cases null-element, null-element-exception, null-then-database and null-piped.
        It "warns as the method call on a null element does, and reads the next database" {
            $nullWarnings = @()
            $next = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbSecond -EnableException
            $rows = @(Get-DbaDbFeatureUsage -InputObject @($null, $next) -WarningVariable nullWarnings -WarningAction SilentlyContinue)
            $nullWarnings.Count | Should -Be 1
            $nullWarnings[0].ToString() | Should -BeLike "*Failure | You cannot call a method on a null-valued expression."
            $rows.Database | Should -BeExactly $dbSecond
        }

        It "throws for a null element under -EnableException" {
            $nullRecord = $null
            try {
                Get-DbaDbFeatureUsage -InputObject @($null) -EnableException
            } catch {
                $nullRecord = $PSItem
            }
            $nullRecord.Exception.Message | Should -BeExactly "You cannot call a method on a null-valued expression."
            $nullRecord.CategoryInfo.Category | Should -Be InvalidOperation
        }

        It "reads nothing for a piped null" {
            $pipedNullWarnings = @()
            $rows = @($null | Get-DbaDbFeatureUsage -WarningVariable pipedNullWarnings)
            $rows.Count | Should -Be 0
            $pipedNullWarnings.Count | Should -Be 0
        }
    }

    Context "Databases it cannot read" {
        BeforeAll {
            # The object read before the database went offline still says accessible, so the query itself fails: case query-failure.
            $staleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $staleDatabase = $staleServer.Databases[$dbStale]
            $staleNext = $staleServer.Databases[$dbFirst]
            $staleWasAccessible = $staleDatabase.IsAccessible
            $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$dbStale] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        }

        AfterAll {
            $staleServer.ConnectionContext.Disconnect()
        }

        It "warns that an offline database is not accessible and reads the next" {
            $offlineWarnings = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbOffline, $dbSecond -WarningVariable offlineWarnings -WarningAction SilentlyContinue)
            $offlineWarnings.Count | Should -Be 1
            $offlineWarnings[0].ToString() | Should -BeLike "*The database ``[$dbOffline``] is not accessible. Skipping database."
            $rows.Database | Should -BeExactly $dbSecond
        }

        It "throws for that database under -EnableException" -Tag NativeChecklist:enable-exception {
            { Get-DbaDbFeatureUsage @splatRead -Database $dbOffline, $dbSecond } | Should -Throw "*The database ``[$dbOffline``] is not accessible. Skipping database.*"
        }

        It "warns 'Failure' with the server's message when the query fails, and reads the next" {
            $staleWasAccessible | Should -BeTrue
            $queryWarnings = @()
            $rows = @(Get-DbaDbFeatureUsage -InputObject @($staleDatabase, $staleNext) -WarningVariable queryWarnings -WarningAction SilentlyContinue)
            $queryWarnings.Count | Should -Be 1
            $queryWarnings[0].ToString() | Should -BeLike "*Failure | Database '$dbStale' cannot be opened because it is offline."
            $rows.Database | Should -BeExactly $dbFirst
        }

        It "throws the server's error when the query fails under -EnableException" {
            $queryRecord = $null
            try {
                $staleDatabase | Get-DbaDbFeatureUsage -EnableException
            } catch {
                $queryRecord = $PSItem
            }
            $queryRecord.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbFeatureUsage*"
            $queryRecord.CategoryInfo.Category | Should -Be NotSpecified
            $queryRecord.Exception.Message | Should -BeExactly "Database '$dbStale' cannot be opened because it is offline."
            $queryRecord.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException
        }
    }

    Context "Connection failures" {
        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $connectErrors = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbSecond -WarningVariable connectWarnings -WarningAction SilentlyContinue -ErrorVariable connectErrors)
            ($connectWarnings -join " ") | Should -BeLike "*Get-DbaDatabase*Failure*"
            $rows.Database | Should -BeExactly $dbSecond

            # The caller's -ErrorVariable holds the nested Get-DbaDatabase Stop-Function record, as the pinned nested call puts it there
            # (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the caught Connect-DbaInstance records and blank
            # entries: accepted difference omitted-consequential-records.
            $connectErrors = @($connectErrors)
            $connectErrors.Count | Should -Be 1
            $connectErrors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $connectErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
            "$($connectErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $connectErrors[0].Exception.Message | Should -Not -BeNullOrEmpty
            $connectErrors[0].Exception.InnerException | Should -Not -BeNullOrEmpty
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $falseErrors = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbSecond -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue -ErrorVariable falseErrors)
            ($falseWarnings -join " ") | Should -BeLike "*Get-DbaDatabase*Failure*"
            $rows.Database | Should -BeExactly $dbSecond
            @($falseErrors).Count | Should -Be 1
            @($falseErrors)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        }

        It "warns and moves on under -EnableException too, which the pinned function never passes to the nested call" {
            $enableWarnings = @()
            $enableErrors = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbSecond -EnableException -WarningVariable enableWarnings -WarningAction SilentlyContinue -ErrorVariable enableErrors)
            ($enableWarnings -join " ") | Should -BeLike "*Get-DbaDatabase*Failure*"
            $rows.Database | Should -BeExactly $dbSecond
            @($enableErrors).Count | Should -Be 1
            @($enableErrors)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE dbo.TestCompression (Column1 nvarchar(10), Column2 int PRIMARY KEY); ALTER TABLE dbo.TestCompression REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);")
        }

        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $rows.Database | Should -BeExactly $loginDbName
            $rows.Feature | Should -BeExactly "Compression"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Get-DbaDatabase*Failure*Login failed*"
        }

        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbFeatureUsage.ps1 connects through Get-DbaDatabase without passing
        # -EnableException on, so the command only warns. Measured on the pin against this instance, both editions:
        # probes/pin-featureusage-20261101.ps1, case login-without-credential-exception.
        It "only warns without the credential under -EnableException, as the pinned function does" {
            $exceptionWarnings = @()
            $rows = @(Get-DbaDbFeatureUsage -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningVariable exceptionWarnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            ($exceptionWarnings -join " ") | Should -BeLike "*Get-DbaDatabase*Failure*Login failed*"
        }
    }
}

# NativeChecklist azure-sqldb: tested. Measured on the pin, both editions: sys.dm_db_persisted_sku_features answers on Azure SQL
# Database through a connection to the database, one to the logical server and an instance name with a credential, and lists
# TransparentDatabaseEncryption and, once a compressed table exists, Compression. ComputerName is not asserted:
# SERVERPROPERTY('MachineName') has no value on that engine, as in every command with this query shape.
Describe "Get-DbaDbFeatureUsage native on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        function Connect-NativeAzure {
            param([hashtable]$Connection)
            # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    return Connect-DbaInstance @Connection
                } catch {
                    # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -match "timeout|timed out") {
                            $isResuming = $true
                        }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        $splatAzureDatabase = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        $azureServer = Connect-NativeAzure -Connection $splatAzureDatabase
        $azureEdition = $azureServer.DatabaseEngineEdition.ToString()
        $splatAzureLogicalServer = @{
            SqlInstance         = $TestConfig.AzureSqlDbServer
            SqlCredential       = $TestConfig.AzureSqlDbCred
            ConnectTimeout      = 60
            NonPooledConnection = $true
            EnableException     = $true
        }
        $azureLogicalServer = Connect-NativeAzure -Connection $splatAzureLogicalServer

        # Six legs share the database: a unique name and cleanup.
        $azureTable = "native_feature_" + [Guid]::NewGuid().ToString("N")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureTable] (Column1 nvarchar(10), Column2 int PRIMARY KEY); ALTER TABLE dbo.[$azureTable] REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureTable]') IS NOT NULL DROP TABLE dbo.[$azureTable];")
        }
        if ($azureLogicalServer) {
            $azureLogicalServer.ConnectionContext.Disconnect()
        }
    }

    It "reads the database's features through a connection to it" -Tag "NativeChecklist:azure-sqldb" {
        $azureEdition | Should -BeExactly "SqlDatabase"
        $rows = @(Get-DbaDbFeatureUsage -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $rows.Feature | Should -Contain "Compression"
        $rows.Feature | Should -Contain "TransparentDatabaseEncryption"
        $rows.Database | Sort-Object -Unique | Should -BeExactly $TestConfig.AzureSqlDbName
        $row = $rows | Where-Object Feature -eq "Compression"
        $row | Should -BeOfType System.Data.DataRow
        $row.Id | Should -BeOfType System.Int32
        $row.InstanceName | Should -BeExactly "MSSQLSERVER"
        $row.SqlInstance | Should -Not -BeNullOrEmpty
    }

    It "reads every database through a connection to the logical server" {
        $rows = @(Get-DbaDbFeatureUsage -SqlInstance $azureLogicalServer -EnableException)
        $rows.Feature | Should -Contain "Compression"
        $rows.Database | Sort-Object -Unique | Should -BeExactly $TestConfig.AzureSqlDbName
    }

    It "reads an instance name with a credential" {
        $rows = @(Get-DbaDbFeatureUsage -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException)
        $rows.Feature | Should -Contain "Compression"
    }

    It "reads a piped database" {
        $rows = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbFeatureUsage -EnableException)
        $rows.Feature | Should -Contain "Compression"
    }
}
