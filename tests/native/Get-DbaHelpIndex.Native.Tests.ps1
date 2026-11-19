#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaHelpIndex",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command; the pinned function does not declare SupportsShouldProcess.

Describe "Native Get-DbaHelpIndex" -Tag IntegrationTests {
    BeforeAll {
        # Setup and cleanup SQL runs on a connection of its own; the command gets $hiServer.
        $hiAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
        $hiServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $hiSuffix = [Guid]::NewGuid().ToString("N")
        $hiDbName = "native_helpidx_$hiSuffix"
        $hiFragDbName = "native_helpidx_frag_$hiSuffix"
        $hiBadInstance = "TCP:127.0.0.1,1"
        # A name outside code page 1252, written with [char] so Windows PowerShell reads this file the same way.
        $hiOmegaTable = "hi_" + [char]0x03A9 + "_tbl"
        $hiWideColumns = @(1..40 | ForEach-Object { "include_column_with_a_long_name_{0:D2}" -f $PSItem })

        $hiDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $hiAdmin, $hiDbName
        # A code page 1252 collation whatever the server's default: a varchar literal there cannot hold the omega.
        $hiDatabase.Collation = "SQL_Latin1_General_CP1_CI_AS"
        $hiDatabase.Create()
        $hiWideDefinition = ($hiWideColumns | ForEach-Object { "[$PSItem] int NULL" }) -join ", "
        $hiWideInclude = ($hiWideColumns | ForEach-Object { "[$PSItem]" }) -join ", "
        $hiDatabase.ExecuteNonQuery(@"
CREATE TABLE dbo.hi_pk (col1 varchar(50) PRIMARY KEY, col2 int);
INSERT INTO dbo.hi_pk VALUES ('value1', 1), ('value2', 2);
CREATE TABLE dbo.hi_unused (c1 int, c2 int, c3 int);
CREATE NONCLUSTERED INDEX hi_unused_idx ON dbo.hi_unused (c1) INCLUDE (c3);
CREATE TABLE dbo.hi_stats (k int NOT NULL PRIMARY KEY, v int NULL);
INSERT INTO dbo.hi_stats VALUES (1, 1), (2, 2);
CREATE STATISTICS hi_col_stats ON dbo.hi_stats (v);
CREATE TABLE dbo.hi_heap (a int NULL, b int NULL);
CREATE NONCLUSTERED INDEX hi_heap_idx ON dbo.hi_heap (a);
CREATE TABLE dbo.[$hiOmegaTable] (k int NOT NULL PRIMARY KEY);
CREATE TABLE dbo.hi_wide (k int NOT NULL PRIMARY KEY, $hiWideDefinition);
CREATE NONCLUSTERED INDEX hi_wide_idx ON dbo.hi_wide (k) INCLUDE ($hiWideInclude);
CREATE TABLE dbo.hi_mru (k int NOT NULL PRIMARY KEY, v int NULL);
INSERT INTO dbo.hi_mru (k, v) SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 1 FROM sys.all_columns;
"@)

        # Random single-row inserts split pages; taking the database offline and online then clears its index usage
        # statistics, so the fragmented index has no row in sys.dm_db_index_usage_stats.
        $hiFragDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $hiAdmin, $hiFragDbName
        $hiFragDatabase.Create()
        $hiFragDatabase.ExecuteNonQuery(@"
CREATE TABLE dbo.hi_frag (id uniqueidentifier NOT NULL DEFAULT NEWID() PRIMARY KEY CLUSTERED, filler char(800) NOT NULL DEFAULT 'x');
DECLARE @i int = 0;
WHILE @i < 2000 BEGIN INSERT INTO dbo.hi_frag DEFAULT VALUES; SET @i += 1; END;
"@)
        $null = $hiAdmin.ConnectionContext.ExecuteNonQuery("USE [master]; ALTER DATABASE [$hiFragDbName] SET OFFLINE WITH ROLLBACK IMMEDIATE; ALTER DATABASE [$hiFragDbName] SET ONLINE;")
        $hiAdmin.Databases.Refresh()
        $hiServer.Databases.Refresh()
    }

    AfterAll {
        $hiAdmin.Databases.Refresh()
        foreach ($name in $hiDbName, $hiFragDbName) {
            if ($hiAdmin.Databases[$name]) {
                # KillDatabase ends every other session in the database before the drop.
                $hiAdmin.KillDatabase($name)
            }
        }
        $hiAdmin.ConnectionContext.Disconnect()
    }

    It "returns the pinned properties in the order the pinned hashtable gives them" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_pk -EnableException)
        $rows.Count | Should -Be 1
        # The pin builds an @{} hashtable of four entries, adds every property PowerShell reports for the DataRow, then
        # casts it to [pscustomobject]. The same construction here, on a DataRow with the query's columns.
        $probeTable = New-Object System.Data.DataTable
        foreach ($column in "FullObjectName", "IndexType", "IndexName", "StatisticsName", "KeyColumns", "IncludeColumns", "FilterDefinition", "FillFactor", "DataCompression", "IndexReads", "IndexUpdates", "SizeKB", "IndexRows", "IndexLookups", "MostRecentlyUsed", "StatsSampleRows", "StatsRowMods", "HistogramSteps", "StatsLastUpdated", "IndexFragInPercent") {
            $null = $probeTable.Columns.Add($column)
        }
        $probeRow = $probeTable.NewRow()
        $probeTable.Rows.Add($probeRow)
        $mapping = @{
            FullObjectName   = "Object"
            IndexName        = "Index"
            StatisticsName   = "Statistics"
            SizeKB           = "Size"
            MostRecentlyUsed = "MostRecentlyUsed"
        }
        $expected = @{
            ComputerName = 1
            InstanceName = 1
            SqlInstance  = 1
            Database     = 1
        }
        foreach ($property in $probeRow.PSObject.Properties) {
            $name = if ($mapping.ContainsKey($property.Name)) { $mapping[$property.Name] } else { $property.Name }
            $expected[$name] = 1
        }
        @($rows[0].PSObject.Properties.Name) | Should -BeExactly @(([pscustomobject]$expected).PSObject.Properties.Name)
        $rows[0].Database | Should -BeExactly $hiDbName
        $rows[0].Object | Should -BeExactly "[dbo].[hi_pk]"
        $rows[0].IndexType | Should -BeExactly "CLUSTERED (PRIMARY KEY)"
        $rows[0].KeyColumns | Should -BeExactly "col1"
        $rows[0].SqlInstance | Should -BeExactly $hiServer.DomainInstanceName
        # Piped to Should, a DataTable would be enumerated row by row.
        ($rows[0].Table -is [System.Data.DataTable]) | Should -BeTrue
    }

    It "reports the size in KB as text, and as a dbasize of the bytes under -Raw" {
        $splatSize = @{
            SqlInstance     = $hiServer
            Database        = $hiDbName
            ObjectName      = "dbo.hi_pk"
            EnableException = $true
        }
        $sizeKb = $hiAdmin.ConnectionContext.ExecuteScalar("SELECT (SUM(in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) * 8192) / 1024 FROM [$hiDbName].sys.dm_db_partition_stats WHERE object_id = OBJECT_ID(N'[$hiDbName].dbo.hi_pk') AND index_id = 1")
        $formatted = @(Get-DbaHelpIndex @splatSize)
        $formatted[0].Size | Should -BeExactly ("{0:N0}" -f $sizeKb)
        $formatted[0].IndexRows | Should -BeExactly ("{0:N0}" -f 2)
        $raw = @(Get-DbaHelpIndex @splatSize -Raw)
        $raw[0].Size.Byte | Should -Be ($sizeKb * 1024)
        $raw[0].IndexRows | Should -Be 2
    }

    It "reports no MostRecentlyUsed for an index never used" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_unused -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Index | Should -BeExactly "hi_unused_idx"
        $rows[0].MostRecentlyUsed | Should -BeNullOrEmpty
        $rows[0].IncludeColumns | Should -BeExactly "c3"
    }

    It "treats -IncludeStats:`$false as leaving statistics out" -Tag "NativeChecklist:switch-false" {
        # An index row's Statistics is DBNull; a statistics-only row names its statistic.
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_stats -IncludeStats:$false -EnableException)
        @($rows | Where-Object { $PSItem.Statistics -is [string] }).Count | Should -Be 0
        $rows.Count | Should -Be 1
        $withStats = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_stats -IncludeStats -EnableException)
        @($withStats | Where-Object { $PSItem.Statistics -is [string] }).Statistics | Should -Contain "hi_col_stats"
    }

    It "adds the column data types under -IncludeDataTypes" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_pk -IncludeDataTypes -EnableException)
        $rows[0].KeyColumns | Should -BeExactly "col1 (varchar)"
    }

    It "processes every piped database" -Tag "NativeChecklist:pipeline-multiple" {
        $rows = @(Get-DbaDatabase -SqlInstance $hiServer -Database $hiDbName, $hiFragDbName -EnableException | Get-DbaHelpIndex -EnableException)
        @($rows.Database | Select-Object -Unique | Sort-Object) | Should -BeExactly @(@($hiDbName, $hiFragDbName) | Sort-Object)
    }

    It "warns for a failed connection and still processes the other instance" -Tag "NativeChecklist:multi-instance-failure" {
        $hiWarnings = @()
        $splatInstances = @{
            SqlInstance     = $hiBadInstance, $hiServer
            Database        = $hiDbName
            ObjectName      = "dbo.hi_pk"
            WarningAction   = "SilentlyContinue"
            WarningVariable = "hiWarnings"
        }
        $rows = @(Get-DbaHelpIndex @splatInstances)
        $rows.Count | Should -Be 1
        $rows[0].Object | Should -BeExactly "[dbo].[hi_pk]"
        ($hiWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error under -EnableException before any database is read" -Tag "NativeChecklist:enable-exception" {
        $observed = New-Object System.Collections.ArrayList
        $caught = $null
        try {
            Get-DbaHelpIndex -SqlInstance $hiServer, $hiBadInstance -Database $hiDbName -EnableException | ForEach-Object { $null = $observed.Add($PSItem) }
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        # The pin connects every instance before it reads any database.
        $observed.Count | Should -Be 0
    }

    It "warns that an offline database is not accessible and goes on with the next one" {
        $offlineName = "native_helpidx_offline_$hiSuffix"
        $offline = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $hiAdmin, $offlineName
        $offline.Create()
        try {
            $null = $hiAdmin.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $hiServer.Databases.Refresh()
            $hiWarnings = @()
            $splatOffline = @{
                SqlInstance     = $hiServer
                Database        = $offlineName, $hiDbName
                ObjectName      = "dbo.hi_pk"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "hiWarnings"
            }
            $rows = @(Get-DbaHelpIndex @splatOffline)
            ($hiWarnings -join " ") | Should -BeLike "*``[$offlineName``] is not accessible. Skipping.*"
            $rows.Count | Should -Be 1
            $rows[0].Database | Should -BeExactly $hiDbName
        } finally {
            $null = $hiAdmin.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$offlineName') IS NOT NULL BEGIN ALTER DATABASE [$offlineName] SET ONLINE; DROP DATABASE [$offlineName]; END")
            $hiServer.Databases.Refresh()
        }
    }

    It "leaves the caller's connection in the database it was in" {
        $splatCallerConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $callerServer = Connect-DbaInstance @splatCallerConnection
        try {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly "tempdb"
            $rows = @(Get-DbaHelpIndex -SqlInstance $callerServer -Database $hiDbName -ObjectName dbo.hi_pk -EnableException)
            $rows.Count | Should -Be 1
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly "tempdb"
        } finally {
            $callerServer.ConnectionContext.Disconnect()
        }
    }

    It "selects databases by a documented wildcard pattern" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database "native_helpidx_$($hiSuffix.Substring(0, 16))*" -ObjectName dbo.hi_pk -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Database | Should -BeExactly $hiDbName
    }

    It "finds a table whose name is outside the database's code page" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName "dbo.$hiOmegaTable" -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Object | Should -BeExactly "[dbo].[$hiOmegaTable]"
    }

    It "lists every include column of a wide index" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_wide -EnableException | Where-Object Index -eq "hi_wide_idx")
        $rows.Count | Should -Be 1
        $rows[0].IncludeColumns | Should -BeExactly ($hiWideColumns -join ", ")
        $rows[0].KeyColumns | Should -BeExactly "k"
    }

    It "returns column statistics whose id another table's index also has under -IncludeStats" {
        $independent = $hiAdmin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM [$hiDbName].sys.stats s JOIN [$hiDbName].sys.indexes i ON i.index_id = s.stats_id WHERE s.object_id = OBJECT_ID(N'[$hiDbName].dbo.hi_stats') AND s.name = N'hi_col_stats' AND i.object_id = OBJECT_ID(N'[$hiDbName].dbo.hi_heap') AND i.name = N'hi_heap_idx'")
        $independent | Should -Be 1
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -IncludeStats -EnableException | Where-Object Statistics -eq "hi_col_stats")
        $rows.Count | Should -Be 1
        $rows[0].Object | Should -BeExactly "[dbo].[hi_stats]"
        $rows[0].KeyColumns | Should -BeExactly "v"
    }

    It "reports MostRecentlyUsed when a scan and a seek of the index share the latest time" {
        $tieQuery = "SELECT COUNT(*) FROM [$hiDbName].dbo.hi_mru AS a WITH (FORCESCAN) INNER LOOP JOIN [$hiDbName].dbo.hi_mru AS b WITH (FORCESEEK) ON b.k = a.k"
        $readQuery = "SELECT CONVERT(datetime2(0), last_user_scan) AS scanned, CONVERT(datetime2(0), last_user_seek) AS sought, last_user_lookup AS looked FROM sys.dm_db_index_usage_stats WHERE database_id = DB_ID(N'$hiDbName') AND object_id = OBJECT_ID(N'[$hiDbName].dbo.hi_mru') AND index_id = 1"
        # One statement scans and seeks the clustered index; its two times can still round to different seconds.
        $usage = $null
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $null = $hiAdmin.ConnectionContext.ExecuteScalar($tieQuery)
            $usage = $hiAdmin.ConnectionContext.ExecuteWithResults($readQuery).Tables[0].Rows[0]
            if ($usage.scanned -eq $usage.sought) { break }
        }
        $usage.scanned | Should -Be $usage.sought
        $usage.looked | Should -BeOfType System.DBNull
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_mru -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].MostRecentlyUsed | Should -Be $usage.scanned
    }

    It "leaves IndexFragInPercent empty without -IncludeFragmentation" {
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_pk -EnableException)
        $rows[0].IndexFragInPercent | Should -BeExactly ""
        $raw = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiDbName -ObjectName dbo.hi_pk -Raw -EnableException)
        $raw[0].IndexFragInPercent | Should -BeOfType System.DBNull
    }

    It "reports the fragmentation of an index with no usage statistics" {
        $unused = $hiAdmin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.dm_db_index_usage_stats WHERE database_id = DB_ID(N'$hiFragDbName')")
        $unused | Should -Be 0
        $fragmentation = $hiAdmin.ConnectionContext.ExecuteScalar("SELECT AVG(avg_fragmentation_in_percent) FROM sys.dm_db_index_physical_stats(DB_ID(N'$hiFragDbName'), OBJECT_ID(N'[$hiFragDbName].dbo.hi_frag'), 1, NULL, 'DETAILED')")
        $fragmentation | Should -BeGreaterThan 0
        $rows = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiFragDbName -ObjectName dbo.hi_frag -IncludeFragmentation -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].IndexFragInPercent | Should -BeExactly ("{0:F2}" -f $fragmentation)
        $raw = @(Get-DbaHelpIndex -SqlInstance $hiServer -Database $hiFragDbName -ObjectName dbo.hi_frag -IncludeFragmentation -Raw -EnableException)
        $raw[0].IndexFragInPercent | Should -BeOfType System.Double
        [Math]::Abs($raw[0].IndexFragInPercent - $fragmentation) | Should -BeLessThan 0.001
    }
}

Describe "Native Get-DbaHelpIndex on Azure SQL Database" -Tag IntegrationTests {
    It "returns the indexes of a table in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        $azureTable = "native_helpidx_$([Guid]::NewGuid().ToString("N"))"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTable] ([k] int NOT NULL, [v] int NULL); CREATE INDEX [ix_azure] ON [dbo].[$azureTable] ([k]) INCLUDE ([v]);")
            $splatAzure = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                ObjectName      = "dbo.$azureTable"
                EnableException = $true
            }
            $azureRows = @(Get-DbaHelpIndex @splatAzure)
            $azureRows.Count | Should -Be 1
            $azureRows[0].Index | Should -BeExactly "ix_azure"
            $azureRows[0].KeyColumns | Should -BeExactly "k"
            $azureRows[0].IncludeColumns | Should -BeExactly "v"
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTable]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTable];")
        }
    }
}

Describe "Native Get-DbaHelpIndex over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_helpidx_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE dbo.login_idx ([k] int NOT NULL PRIMARY KEY);")
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
                ObjectName      = "dbo.login_idx"
                EnableException = $true
            }
            $loginRows = @(Get-DbaHelpIndex @splatLogin)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Object | Should -BeExactly "[dbo].[login_idx]"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            @(Get-DbaHelpIndex @splatLoginNoCredential).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaHelpIndex -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
