#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaDbDuplicateIndex",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command; the pinned function does not declare SupportsShouldProcess.

Describe "Native Find-DbaDbDuplicateIndex" -Tag IntegrationTests {
    BeforeAll {
        $dupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dupSuffix = [Guid]::NewGuid().ToString("N")
        $dupDbName = "native_dupidx_$dupSuffix"
        $dupDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $dupServer, $dupDbName
        # Case-insensitive whatever the server's default: its metadata, filter_definition among it, compares in this collation.
        $dupDatabase.Collation = "SQL_Latin1_General_CP1_CI_AS"
        $dupDatabase.Create()
        $dupDatabase.ExecuteNonQuery(@"
CREATE TABLE dbo.dup_exact ([a&b<c>] int NOT NULL, [other] int NULL);
CREATE INDEX ix_dup_exact_1 ON dbo.dup_exact ([a&b<c>]);
CREATE INDEX ix_dup_exact_2 ON dbo.dup_exact ([a&b<c>]);
CREATE TABLE dbo.dup_prefix ([CustomerID] int NOT NULL, [OrderDate] datetime NULL);
CREATE INDEX ix_dup_prefix_short ON dbo.dup_prefix ([CustomerID]);
CREATE INDEX ix_dup_prefix_long ON dbo.dup_prefix ([CustomerID], [OrderDate]);
CREATE TABLE dbo.dup_like ([a_b] int NULL, [axb] int NULL, [c] int NULL);
CREATE INDEX ix_dup_like_1 ON dbo.dup_like ([a_b]);
CREATE INDEX ix_dup_like_2 ON dbo.dup_like ([axb], [c]);
CREATE TABLE dbo.dup_none ([x] int NULL, [y] int NULL);
CREATE INDEX ix_dup_none_1 ON dbo.dup_none ([x]);
CREATE INDEX ix_dup_none_2 ON dbo.dup_none ([y]);
"@)
        $dupServer.Databases.Refresh()
        $splatSecondConnection = @{
            SqlInstance         = $dupServer
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $dupSecondServer = Connect-DbaInstance @splatSecondConnection
        $dupBadInstance = "TCP:127.0.0.1,1"
        # Setup and cleanup SQL runs on a connection of its own: the Server objects given to the command are left in
        # the database they queried, with their own state.
        $dupAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
    }

    AfterAll {
        $dupSecondServer.ConnectionContext.Disconnect()
        $dupServer.ConnectionContext.Disconnect()
        $dupAdmin.Databases.Refresh()
        if ($dupAdmin.Databases[$dupDbName]) {
            # KillDatabase ends every other session in the database before the drop.
            $dupAdmin.KillDatabase($dupDbName)
        }
        $dupAdmin.ConnectionContext.Disconnect()
    }

    It "returns the exact duplicates as rows with the pinned columns" {
        $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -EnableException)
        @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_exact_1", "ix_dup_exact_2")
        $rows[0] | Should -BeOfType System.Data.DataRow
        $columns = @($rows[0].Table.Columns.ColumnName)
        $columns | Should -BeExactly @("DatabaseName", "TableName", "IndexName", "KeyColumns", "IncludedColumns", "IndexType", "IndexSizeMB", "CompressionDescription", "RowCount", "IsDisabled", "IsFiltered", "IsUnique")
        $rows[0].DatabaseName | Should -BeExactly $dupDbName
        $rows[0].TableName | Should -BeExactly "dbo.dup_exact"
        $rows[0].IndexType | Should -BeExactly "NONCLUSTERED"
        $rows[0].CompressionDescription | Should -BeExactly "NONE"
    }

    It "treats -IncludeOverlapping:`$false as the exact search" -Tag "NativeChecklist:switch-false" {
        $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -IncludeOverlapping:$false -EnableException)
        @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_exact_1", "ix_dup_exact_2")
    }

    It "shows column names with XML special characters as they are" {
        $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -EnableException)
        @($rows.KeyColumns | Select-Object -Unique) | Should -BeExactly @("a&b<c> ASC")
    }

    It "reports indexes whose key columns start with another index's key columns under -IncludeOverlapping" {
        $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -IncludeOverlapping -EnableException)
        @($rows | Where-Object TableName -eq "dbo.dup_prefix" | ForEach-Object IndexName | Sort-Object) | Should -BeExactly @("ix_dup_prefix_long", "ix_dup_prefix_short")
        @($rows | Where-Object TableName -eq "dbo.dup_exact").Count | Should -Be 2
        @($rows | Where-Object TableName -eq "dbo.dup_like").Count | Should -Be 0
        @($rows | Where-Object TableName -eq "dbo.dup_none").Count | Should -Be 0
    }

    It "selects databases by a documented wildcard pattern" {
        $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database "native_dupidx_$($dupSuffix.Substring(0, 16))*" -EnableException)
        @($rows.DatabaseName | Select-Object -Unique) | Should -BeExactly @($dupDbName)
        @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_exact_1", "ix_dup_exact_2")
    }

    It "leaves the caller's connection in the database it was in" {
        # As the pinned Database.Query script method does (#10555). The connection starts in tempdb and is not pooled,
        # because a pooled connection reconnects at its default database.
        $splatCallerConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $callerServer = Connect-DbaInstance @splatCallerConnection
        try {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly "tempdb"
            $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $callerServer -Database $dupDbName -EnableException)
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_exact_1", "ix_dup_exact_2")
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly "tempdb"
        } finally {
            $callerServer.ConnectionContext.Disconnect()
        }
    }

    It "warns for a failed connection and continues with the next piped server" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $dupWarnings = @()
        $splatPipeline = @{
            Database        = $dupDbName
            WarningAction   = "SilentlyContinue"
            WarningVariable = "dupWarnings"
        }
        $rows = @(@($dupServer, $dupBadInstance, $dupSecondServer) | Find-DbaDbDuplicateIndex @splatPipeline)
        $rows.Count | Should -Be 4
        ($dupWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error under -EnableException after the earlier output" -Tag "NativeChecklist:enable-exception" {
        $observed = New-Object System.Collections.ArrayList
        $caught = $null
        try {
            @($dupServer, $dupBadInstance, $dupSecondServer) |
                Find-DbaDbDuplicateIndex -Database $dupDbName -EnableException |
                ForEach-Object { $null = $observed.Add($PSItem) }
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        $observed.Count | Should -Be 2
    }

    It "warns Query failure for a database it cannot query and goes on with the next one" {
        $dupWarnings = @()
        $splatMissing = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Database        = "native_dupidx_offline_$dupSuffix", $dupDbName
            WarningAction   = "SilentlyContinue"
            WarningVariable = "dupWarnings"
        }
        $offlineName = "native_dupidx_offline_$dupSuffix"
        $offline = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $dupAdmin, $offlineName
        $offline.Create()
        try {
            $null = $dupAdmin.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $rows = @(Find-DbaDbDuplicateIndex @splatMissing)
            ($dupWarnings -join " ") | Should -BeLike "*Query failure*"
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_exact_1", "ix_dup_exact_2")
        } finally {
            $null = $dupAdmin.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$offlineName') IS NOT NULL BEGIN ALTER DATABASE [$offlineName] SET ONLINE; DROP DATABASE [$offlineName]; END")
        }
    }

    Context "Filtered indexes" {
        BeforeAll {
            # Runs after the tests above, which count every index of the database. Two filtered indexes share a filter;
            # the third has the same key but another filter.
            $dupFilterTable = "[$dupDbName].[dbo].[dup_filter]"
            $null = $dupAdmin.ConnectionContext.ExecuteNonQuery(@"
CREATE TABLE $dupFilterTable ([CustomerID] int NOT NULL, [Status] int NULL);
CREATE INDEX ix_dup_filter_open ON $dupFilterTable ([CustomerID]) WHERE [Status] = 0;
CREATE INDEX ix_dup_filter_closed ON $dupFilterTable ([CustomerID]) WHERE [Status] = 1;
CREATE INDEX ix_dup_filter_open_again ON $dupFilterTable ([CustomerID]) WHERE [Status] = 0;
"@)
            # The database is case-insensitive and the column case-sensitive: 'open' and 'OPEN' select different rows, though the two
            # filter definitions compare equal in the database's collation.
            $dupCaseTable = "[$dupDbName].[dbo].[dup_filter_case]"
            $null = $dupAdmin.ConnectionContext.ExecuteNonQuery(@"
CREATE TABLE $dupCaseTable ([CustomerID] int NOT NULL, [Status] varchar(10) COLLATE Latin1_General_CS_AS NULL);
CREATE INDEX ix_dup_case_lower ON $dupCaseTable ([CustomerID]) WHERE [Status] = 'open';
CREATE INDEX ix_dup_case_upper ON $dupCaseTable ([CustomerID]) WHERE [Status] = 'OPEN';
CREATE INDEX ix_dup_case_lower_again ON $dupCaseTable ([CustomerID]) WHERE [Status] = 'open';
"@)
        }

        AfterAll {
            $null = $dupAdmin.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'$dupFilterTable', N'U') IS NOT NULL DROP TABLE $dupFilterTable; IF OBJECT_ID(N'$dupCaseTable', N'U') IS NOT NULL DROP TABLE $dupCaseTable;")
        }

        It "reports filtered indexes as exact duplicates only when their filters match" {
            $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -EnableException | Where-Object TableName -eq "dbo.dup_filter")
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_filter_open", "ix_dup_filter_open_again")
        }

        It "reports filtered indexes as overlapping only when their filters match" {
            $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -IncludeOverlapping -EnableException | Where-Object TableName -eq "dbo.dup_filter")
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_filter_open", "ix_dup_filter_open_again")
        }

        It "reports filtered indexes as exact duplicates only when their filters match in case" {
            $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -EnableException | Where-Object TableName -eq "dbo.dup_filter_case")
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_case_lower", "ix_dup_case_lower_again")
        }

        It "reports filtered indexes as overlapping only when their filters match in case" {
            $rows = @(Find-DbaDbDuplicateIndex -SqlInstance $dupServer -Database $dupDbName -IncludeOverlapping -EnableException | Where-Object TableName -eq "dbo.dup_filter_case")
            @($rows.IndexName | Sort-Object) | Should -BeExactly @("ix_dup_case_lower", "ix_dup_case_lower_again")
        }
    }
}

Describe "Native Find-DbaDbDuplicateIndex on Azure SQL Database" -Tag IntegrationTests {
    It "finds duplicate indexes in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: unique names and cleanup.
        $azureTable = "native_dupidx_$([Guid]::NewGuid().ToString("N"))"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTable] ([k] int NOT NULL); CREATE INDEX [ix_1] ON [dbo].[$azureTable] ([k]); CREATE INDEX [ix_2] ON [dbo].[$azureTable] ([k]);")
            $azureRows = @(Find-DbaDbDuplicateIndex -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException | Where-Object TableName -eq "dbo.$azureTable")
            @($azureRows.IndexName | Sort-Object) | Should -BeExactly @("ix_1", "ix_2")
            $azureRows[0].DatabaseName | Should -BeExactly $TestConfig.AzureSqlDbName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTable]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTable];")
        }
    }
}

Describe "Native Find-DbaDbDuplicateIndex over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_dupidx_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE dbo.login_dup ([k] int NOT NULL); CREATE INDEX ix_login_1 ON dbo.login_dup ([k]); CREATE INDEX ix_login_2 ON dbo.login_dup ([k]);")
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
            $splatLogin = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Find-DbaDbDuplicateIndex @splatLogin)
            @($loginRows.IndexName | Sort-Object) | Should -BeExactly @("ix_login_1", "ix_login_2")
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            @(Find-DbaDbDuplicateIndex @splatLoginNoCredential).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Find-DbaDbDuplicateIndex -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
