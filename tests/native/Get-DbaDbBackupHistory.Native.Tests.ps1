#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbBackupHistory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads msdb.
# NativeChecklist: azure-sqldb N/A -- The command reads the msdb backup tables, which apply to SQL Server and Azure SQL Managed Instance only (https://learn.microsoft.com/sql/relational-databases/system-tables/backupset-transact-sql); Azure SQL Database has no msdb to name, no three-part cross-database queries and no BACKUP syntax (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server). It refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does; "Native Get-DbaDbBackupHistory refuses Azure SQL Database" below proves the refusal.

Describe "Native Get-DbaDbBackupHistory" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $backupDir = "$($TestConfig.Temp)\$CommandName-$random"
        $null = New-Item -ItemType Directory -Path $backupDir
        $server = Connect-DbaInstance -SqlInstance $instance

        # A statement on the instance's own connection, in master: three-part names, never USE.
        function Invoke-NativeSql {
            param([string]$Sql)
            $server.Query($Sql)
        }

        function Add-NativeLog {
            param([string]$Database, [int]$Rows = 1000)
            $null = Invoke-NativeSql "BEGIN TRANSACTION; DECLARE @i int = 0; WHILE @i < $Rows BEGIN INSERT [$Database].dbo.history DEFAULT VALUES; SET @i += 1; END; COMMIT;"
        }

        function Remove-NativeDatabase {
            param([string[]]$Name)
            foreach ($database in $Name) {
                $escaped = $database.Replace("'", "''")
                $quoted = $database.Replace("]", "]]")
                $null = Invoke-NativeSql "IF DB_ID(N'$escaped') IS NOT NULL BEGIN ALTER DATABASE [$quoted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$quoted]; END; EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$escaped';"
            }
        }

        # One database in full recovery with a striped full, a differential, two logs and a copy-only full.
        $dbName = "dbatoolsci_nhist_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$dbName]; ALTER DATABASE [$dbName] SET RECOVERY FULL;"
        $null = Invoke-NativeSql "CREATE TABLE [$dbName].dbo.history (x char(1000) DEFAULT 'x');"
        $fullPaths = "$backupDir\full1.bak", "$backupDir\full2.bak"
        $null = Invoke-NativeSql "BACKUP DATABASE [$dbName] TO DISK = N'$($fullPaths[0])', DISK = N'$($fullPaths[1])';"
        Add-NativeLog -Database $dbName -Rows 10
        $null = Invoke-NativeSql "BACKUP DATABASE [$dbName] TO DISK = N'$backupDir\diff.bak' WITH DIFFERENTIAL;"
        Add-NativeLog -Database $dbName -Rows 10
        $null = Invoke-NativeSql "BACKUP LOG [$dbName] TO DISK = N'$backupDir\log1.trn';"
        Add-NativeLog -Database $dbName -Rows 10
        $null = Invoke-NativeSql "BACKUP LOG [$dbName] TO DISK = N'$backupDir\log2.trn';"
        $null = Invoke-NativeSql "BACKUP DATABASE [$dbName] TO DISK = N'$backupDir\copy.bak' WITH COPY_ONLY;"

        # The same history read independently of the command, oldest first.
        $backupRows = @(Invoke-NativeSql "SELECT backup_set_id, type, first_lsn, last_lsn, database_backup_lsn, checkpoint_lsn, backup_size, compressed_backup_size, position, software_major_version, recovery_model, is_copy_only, last_recovery_fork_guid, user_name, key_algorithm, DB_ID(database_name) AS database_id FROM msdb.dbo.backupset WHERE database_name = N'$dbName' ORDER BY backup_set_id")
        $fullRow = $backupRows[0]
        $diffRow = $backupRows[1]
        $lastLogRow = $backupRows[3]
        $copyRow = $backupRows[4]

        $splatHistory = @{
            SqlInstance = $instance
            Database    = $dbName
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-NativeDatabase -Name $dbName
        Remove-Item -Path $backupDir -Recurse -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Grouped output" {
        BeforeAll {
            $history = @(Get-DbaDbBackupHistory @splatHistory)
            $full = $history | Where-Object Type -eq "Full"
        }

        It "returns one object per backup set in the order of the edition's Group-Object, without the copy-only" {
            $history.Count | Should -Be 4
            $expectedTypes = if ($PSVersionTable.PSEdition -eq "Core") { "Full", "Differential", "Log", "Log" } else { "Log", "Log", "Differential", "Full" }
            $history.Type | Should -Be $expectedTypes
            ($history.BackupSetId) | Should -Not -Contain "$($copyRow.backup_set_id)"
        }

        It "returns a BackupHistory with the instance names" {
            $full | Should -BeOfType Dataplat.Dbatools.Database.BackupHistory
            $full.ComputerName | Should -Be $server.ComputerName
            $full.InstanceName | Should -Be $server.ServiceName
            $full.SqlInstance | Should -Be $server.DomainInstanceName
            $full.AvailabilityGroupName | Should -BeNullOrEmpty
        }

        It "groups the stripes of a backup set" {
            @($full.Path | Sort-Object) | Should -Be $fullPaths
            @($full.FullName | Sort-Object) | Should -Be $fullPaths
        }

        It "reports what msdb holds for the backup set" {
            $full.Database | Should -Be $dbName
            $full.DatabaseId | Should -Be "$($fullRow.database_id)"
            $full.UserName | Should -Be $fullRow.user_name
            $full.BackupSetId | Should -Be "$($fullRow.backup_set_id)"
            $full.DeviceType | Should -Be "Disk"
            $full.Software | Should -Not -BeNullOrEmpty
            $full.Position | Should -Be $fullRow.position
            $full.FirstLsn | Should -Be ([bigint]$fullRow.first_lsn)
            $full.DatabaseBackupLsn | Should -Be ([bigint]$fullRow.database_backup_lsn)
            $full.CheckpointLsn | Should -Be ([bigint]$fullRow.checkpoint_lsn)
            $full.LastLsn | Should -Be ([bigint]$fullRow.last_lsn)
            $full.SoftwareVersionMajor | Should -Be ([int]$fullRow.software_major_version)
            $full.IsCopyOnly | Should -BeFalse
            $full.LastRecoveryForkGUID | Should -Be $fullRow.last_recovery_fork_guid
            $full.RecoveryModel | Should -Be $fullRow.recovery_model
            $full.EncryptorType | Should -BeExactly ""
            $full.EncryptorThumbprint | Should -BeExactly ""
            $full.KeyAlgorithm | Should -BeExactly "$($fullRow.key_algorithm)"
        }

        It "computes sizes, ratio and duration" {
            $full.TotalSize.Byte | Should -Be ([long]$fullRow.backup_size)
            $full.CompressedBackupSize.Byte | Should -Be ([long]$fullRow.compressed_backup_size)
            $full.CompressionRatio | Should -Be ([double][Math]::Round($fullRow.backup_size / $fullRow.compressed_backup_size, 2))
            ($full.End - $full.Start).TotalSeconds | Should -Be $full.Duration.TotalSeconds
        }

        It "lists the files of the backup set" {
            $files = @($full.FileList)
            $files.Count | Should -Be 2
            $files[0].PSObject.Properties.Name | Should -Be "FileType", "LogicalName", "PhysicalName"
            $files.FileType | Should -Contain "D"
            $files.FileType | Should -Contain "L"
            $files.LogicalName | Should -Contain $dbName
            $full.FileList -is [array] | Should -BeTrue
        }
    }

    Context "Raw output" {
        BeforeAll {
            $rawRows = @(Get-DbaDbBackupHistory @splatHistory -Raw)
        }

        It "returns one object per backup file" {
            $rawRows.Count | Should -Be 5
            @($rawRows | Where-Object Type -eq "Full").Count | Should -Be 2
        }

        It "copies Path to FullName and leaves the rank out" {
            foreach ($row in $rawRows) {
                $row.FullName | Should -Be $row.Path
            }
            $rawRows[0].PSObject.Properties.Name | Should -Not -Contain "BackupSetRank"
            $rawRows[0].PSObject.Properties.Name | Should -Not -Contain "RowState"
            $rawRows[0].PSObject.Properties.Name[-1] | Should -Be "FullName"
        }

        It "-Force -Raw returns every msdb column of every backup file" {
            $forced = @(Get-DbaDbBackupHistory @splatHistory -Force -Raw)
            $forced.Count | Should -Be 5
            $forced[0].database_name | Should -Be $dbName
            $forced[0].PSObject.Properties.Name | Should -Contain "backup_set_uuid"
            $forced[0].PSObject.Properties.Name | Should -Contain "media_set_id2"
        }

        It "-Force returns every msdb column of every backup file" {
            $forced = @(Get-DbaDbBackupHistory @splatHistory -Force)
            $forced.Count | Should -Be 5
            $forced[0].database_name | Should -Be $dbName
            $forced[0].PSObject.Properties.Name | Should -Contain "backup_set_uuid"
            ($forced.physical_device_name | Sort-Object -Unique) | Should -Contain $fullPaths[0]
        }

        It "keeps the columns of the query" {
            $names = $rawRows[0].PSObject.Properties.Name
            $names | Should -Contain "first_lsn"
            $names | Should -Contain "FirstLSN"
            $names | Should -Contain "MediaFamilyId"
            $rawRows[0].PSObject.TypeNames[0] | Should -Be "Selected.System.Management.Automation.PSCustomObject"
        }

        It "leaves the rank out of the -LastFull rows too" {
            $lastRows = @(Get-DbaDbBackupHistory @splatHistory -LastFull -Raw)
            $lastRows.Count | Should -Be 2
            $lastRows[0].PSObject.Properties.Name | Should -Not -Contain "BackupSetRank"
        }
    }

    Context "Last forms" {
        It "-LastFull returns the newest full, not the copy-only" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -LastFull)
            $result.Count | Should -Be 1
            $result[0].BackupSetId | Should -Be "$($fullRow.backup_set_id)"
        }

        It "-LastFull -IncludeCopyOnly returns the copy-only" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -LastFull -IncludeCopyOnly)
            $result[0].BackupSetId | Should -Be "$($copyRow.backup_set_id)"
            $result[0].IsCopyOnly | Should -BeTrue
        }

        It "-LastDiff returns the differential" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -LastDiff)
            $result[0].BackupSetId | Should -Be "$($diffRow.backup_set_id)"
        }

        It "-LastLog returns the newest log" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -LastLog)
            $result[0].BackupSetId | Should -Be "$($lastLogRow.backup_set_id)"
        }

        It "-Last builds the chain in LastLsn order" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -Last)
            $result.Type | Should -Be "Full", "Differential", "Log", "Log"
            $result[-1].BackupSetId | Should -Be "$($lastLogRow.backup_set_id)"
        }

        It "-Last -IgnoreDiffBackup leaves the differential out and keeps both logs" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -Last -IgnoreDiffBackup)
            $result.Type | Should -Be "Full", "Log", "Log"
        }

        It "-Last reports a database without a full and goes on" {
            $missing = "dbatoolsci_nosuch_$random"
            $output = Get-DbaDbBackupHistory -SqlInstance $instance -Database $missing, $dbName -Last -Verbose 4>&1
            $messages = @($output | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] }).Message
            ($messages -join " ") | Should -BeLike "*No Full Backup found for database $missing, skipping*"
            @($output | Where-Object { $PSItem -is [Dataplat.Dbatools.Database.BackupHistory] }).Count | Should -Be 4
        }

        It "-Last -Raw returns the stripes of the full and the rest of the chain" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -Last -Raw)
            $result.Type | Should -Be "Full", "Full", "Differential", "Log", "Log"
            $result[-1].BackupSetId | Should -Be $lastLogRow.backup_set_id
        }

        It "returns every database of a list once under -LastFull" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $dbName, $dbName -LastFull)
            $result.Count | Should -Be 1
        }
    }

    Context "Filters" {
        It "-Type maps the backup types, in any case" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -Type "log", Differential)
            ($result.Type | Sort-Object -Unique) | Should -Be "Differential", "Log"
        }

        It "-DeviceType takes names and numbers" {
            @(Get-DbaDbBackupHistory @splatHistory -DeviceType disk).Count | Should -Be 4
            @(Get-DbaDbBackupHistory @splatHistory -DeviceType 2).Count | Should -Be 4
            @(Get-DbaDbBackupHistory @splatHistory -DeviceType Tape).Count | Should -Be 0
        }

        It "-DeviceType filters the -Last forms" {
            @(Get-DbaDbBackupHistory @splatHistory -DeviceType Tape -LastFull).Count | Should -Be 0
            @(Get-DbaDbBackupHistory @splatHistory -DeviceType Disk -Last).Count | Should -Be 4
        }

        It "-LastLsn keeps the later backups" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -LastLsn ([bigint]$diffRow.last_lsn))
            $result.Type | Should -Be "Log", "Log"
        }

        It "-Since leaves out what finished earlier" {
            @(Get-DbaDbBackupHistory @splatHistory -Since (Get-Date).AddYears(1)).Count | Should -Be 0
        }

        It "-LsnSort orders by the chosen column" {
            $rawResult = @(Get-DbaDbBackupHistory @splatHistory -LsnSort FirstLsn -Raw)
            $rawResult.Count | Should -Be 5
            @($rawResult.first_lsn) | Should -Be @($rawResult.first_lsn | Sort-Object -Descending)

            # Grouped output shows the column on Windows PowerShell 5.1 only: Group-Object sorts by BackupSetId on PowerShell 7.
            $result = @(Get-DbaDbBackupHistory @splatHistory -LsnSort FirstLsn)
            if ($PSVersionTable.PSEdition -eq "Core") {
                @($result.BackupSetId) | Should -Be @($result.BackupSetId | Sort-Object { [int]$PSItem })
            } else {
                @($result.FirstLsn) | Should -Be @($result.FirstLsn | Sort-Object -Descending)
            }
        }

        It "-IncludeCopyOnly adds the copy-only" {
            $result = @(Get-DbaDbBackupHistory @splatHistory -IncludeCopyOnly)
            $result.Count | Should -Be 5
            ($result | Where-Object BackupSetId -eq "$($copyRow.backup_set_id)").IsCopyOnly | Should -BeTrue
        }

        It "-IgnoreDiffBackup leaves the differential out" {
            @(Get-DbaDbBackupHistory @splatHistory -IgnoreDiffBackup).Type | Should -Not -Contain "Differential"
        }

        It "-ExcludeDatabase takes a name out of -Database, in any case" {
            @(Get-DbaDbBackupHistory @splatHistory -ExcludeDatabase $dbName.ToUpper()).Count | Should -Be 0
        }

        It "matches a name with brackets exactly" {
            $bracketName = "dbatoolsci_n[hist]_$random"
            $quoted = $bracketName.Replace("]", "]]")
            try {
                $null = Invoke-NativeSql "CREATE DATABASE [$quoted]; BACKUP DATABASE [$quoted] TO DISK = N'NUL';"
                @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $bracketName).Database | Should -Be $bracketName
            } finally {
                Remove-NativeDatabase -Name $bracketName
            }
        }

        It "reports a failing query as the pin's method fault and returns nothing" {
            $failing = @(Get-DbaDbBackupHistory @splatHistory -DeviceType nosuchdevice -ErrorVariable queryErrors -ErrorAction SilentlyContinue)
            $failing.Count | Should -Be 0
            $queryErrors[0].FullyQualifiedErrorId | Should -BeLike "ExecutionFailureException*"
            $queryErrors[0].Exception.Message | Should -BeLike 'Exception calling "ExecuteWithResults" with "1" argument(s): *'
        }

        It "throws a failing query under -EnableException" {
            { Get-DbaDbBackupHistory @splatHistory -DeviceType nosuchdevice -EnableException } | Should -Throw "*ExecuteWithResults*"
        }
    }

    Context "Parameter checks" {
        It "warns about -AgCheck and returns nothing" {
            $result = Get-DbaDbBackupHistory @splatHistory -AgCheck -WarningVariable agWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $agWarning | Should -BeLike "*Parameter AGCheck is deprecated*Get-DbaAgBackupHistory*"
        }

        It "throws -AgCheck under -EnableException" {
            { Get-DbaDbBackupHistory @splatHistory -AgCheck -EnableException } | Should -Throw "*Parameter AGCheck is deprecated*"
        }

        It "warns about a -Since of another type, a null included" {
            $result = Get-DbaDbBackupHistory @splatHistory -Since $null -WarningVariable sinceWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $sinceWarning | Should -BeLike "*-Since must be either a DateTime or TimeSpan object*"
        }

        It "throws a wrong -Since under -EnableException" {
            { Get-DbaDbBackupHistory @splatHistory -Since "-" -EnableException } | Should -Throw "*-Since must be either a DateTime or TimeSpan object*"
        }

        It "reads the instances from the pipeline and from the parameter" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbBackupHistory -Database $dbName -LastFull).Count | Should -Be 2
            @(Get-DbaDbBackupHistory -SqlInstance $instance, $instance -Database $dbName -LastFull).Count | Should -Be 2
        }

        It "warns about an instance it cannot reach and goes on to the next" -Tag "NativeChecklist:multi-instance-failure" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSqlLogin, $instance -Database $dbName -LastFull -WarningVariable reachWarning -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $reachWarning | Should -Not -BeNullOrEmpty
        }

        It "throws for that instance under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSqlLogin, $instance -Database $dbName -LastFull -EnableException
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "reads switches set to false as not given" -Tag "NativeChecklist:switch-false" {
            $splatFalse = @{
                Last             = $false
                LastFull         = $false
                LastDiff         = $false
                LastLog          = $false
                Raw              = $false
                Force            = $false
                IncludeCopyOnly  = $false
                IncludeMirror    = $false
                IgnoreDiffBackup = $false
                AgCheck          = $false
            }
            $result = @(Get-DbaDbBackupHistory @splatHistory @splatFalse)
            $result.Count | Should -Be 4
            $result[0] | Should -BeOfType Dataplat.Dbatools.Database.BackupHistory
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Unique per leg and run: the instance is shared. NUL keeps the history and leaves no file.
            $loginDb = "dbatoolsci_nhistlogin_$(Get-Random)"
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $null = $loginServer.Query("CREATE DATABASE [$loginDb]; BACKUP DATABASE [$loginDb] TO DISK = N'NUL';")
        }

        AfterAll {
            $null = $loginServer.Query("ALTER DATABASE [$loginDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$loginDb]; EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$loginDb';")
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDb -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -Be $loginDb
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbBackupHistory -SqlInstance $loginInstance -Database $loginDb -WarningVariable loginWarning -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $loginWarning | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            { Get-DbaDbBackupHistory -SqlInstance $loginInstance -Database $loginDb -EnableException } | Should -Throw
        }
    }

    Context "Forked database" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # A full and two logs on the first fork, then a restore of that full, a full and a log on the second.
            $forkDb = "dbatoolsci_nfork_$random"
            $null = Invoke-NativeSql "CREATE DATABASE [$forkDb]; ALTER DATABASE [$forkDb] SET RECOVERY FULL;"
            $null = Invoke-NativeSql "CREATE TABLE [$forkDb].dbo.history (x char(1000) DEFAULT 'x');"
            $null = Invoke-NativeSql "BACKUP DATABASE [$forkDb] TO DISK = N'$backupDir\fork1.bak';"
            Add-NativeLog -Database $forkDb
            $null = Invoke-NativeSql "BACKUP LOG [$forkDb] TO DISK = N'$backupDir\fork1a.trn';"
            Add-NativeLog -Database $forkDb
            $null = Invoke-NativeSql "BACKUP LOG [$forkDb] TO DISK = N'$backupDir\fork1b.trn';"
            $null = Invoke-NativeSql "ALTER DATABASE [$forkDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; RESTORE DATABASE [$forkDb] FROM DISK = N'$backupDir\fork1.bak' WITH REPLACE;"
            # backup_finish_date has second resolution, and the -Last forms take the fork of the newest backup.
            Start-Sleep -Seconds 1
            $null = Invoke-NativeSql "BACKUP DATABASE [$forkDb] TO DISK = N'$backupDir\fork2.bak';"
            Add-NativeLog -Database $forkDb -Rows 10
            $null = Invoke-NativeSql "BACKUP LOG [$forkDb] TO DISK = N'$backupDir\fork2a.trn';"
            $forkRows = @(Invoke-NativeSql "SELECT backup_set_id, first_lsn, last_lsn, last_recovery_fork_guid FROM msdb.dbo.backupset WHERE database_name = N'$forkDb' ORDER BY backup_set_id")
            $firstFork = $forkRows[0].last_recovery_fork_guid
            $secondFork = $forkRows[-1].last_recovery_fork_guid
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-NativeDatabase -Name $forkDb
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "has two forks with first-fork logs past the second full" {
            $firstFork | Should -Not -Be $secondFork
            [bigint]$forkRows[2].last_lsn | Should -BeGreaterThan ([bigint]$forkRows[3].first_lsn)
        }

        It "-LastFull stays silent about the forks and -LastLog names each" {
            $null = Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -LastFull -WarningVariable fullWarning -WarningAction SilentlyContinue
            $fullWarning | Should -BeNullOrEmpty
            $null = Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -LastLog -WarningVariable logWarning -WarningAction SilentlyContinue
            @($logWarning).Count | Should -Be 2
            ($logWarning -join " ") | Should -BeLike "*$forkDb was on Recovery Fork GUID $firstFork (3 backups)*"
            ($logWarning -join " ") | Should -BeLike "*$forkDb was on Recovery Fork GUID $secondFork (2 backups)*"
        }

        It "-Last stays on the fork of the newest backup" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -Last -WarningAction SilentlyContinue)
            $result.Type | Should -Be "Full", "Log"
            ($result.LastRecoveryForkGUID | Sort-Object -Unique) | Should -Be $secondFork
        }

        It "-RecoveryFork restricts -LastFull to that fork" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -LastFull -RecoveryFork $secondFork)
            $result.LastRecoveryForkGUID | Should -Be $secondFork
        }

        It "-RecoveryFork reaches an older fork under -LastFull" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -LastFull -RecoveryFork $firstFork)
            $result.Count | Should -Be 1
            $result.BackupSetId | Should -Be "$($forkRows[0].backup_set_id)"
            $result.LastRecoveryForkGUID | Should -Be $firstFork
        }

        It "-RecoveryFork reaches an older fork under -Last" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -Last -RecoveryFork $firstFork -WarningAction SilentlyContinue)
            $result.Type | Should -Be "Full", "Log", "Log"
            ($result.LastRecoveryForkGUID | Sort-Object -Unique) | Should -Be $firstFork
        }

        It "-RecoveryFork restricts the default form to that fork" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -RecoveryFork $firstFork)
            $result.Count | Should -Be 3
            ($result.LastRecoveryForkGUID | Sort-Object -Unique) | Should -Be $firstFork
        }

        It "-Last -IncludeCopyOnly stays on the fork of the full" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -Last -IncludeCopyOnly -WarningAction SilentlyContinue)
            $result.Type | Should -Be "Full", "Log"
        }

        It "-Last -Raw -IncludeCopyOnly stays on the fork of the full" {
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $forkDb -Last -Raw -IncludeCopyOnly -WarningAction SilentlyContinue)
            $result.Type | Should -Be "Full", "Log"
            ($result.last_recovery_fork_guid | Sort-Object -Unique) | Should -Be $secondFork
        }
    }
}

Describe "Native Get-DbaDbBackupHistory corrections" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance

        function Invoke-NativeSql {
            param([string]$Sql)
            $server.Query($Sql)
        }

        function Remove-NativeDatabase {
            param([string[]]$Name)
            foreach ($database in $Name) {
                $escaped = $database.Replace("'", "''")
                $quoted = $database.Replace("]", "]]")
                $null = Invoke-NativeSql "IF DB_ID(N'$escaped') IS NOT NULL BEGIN ALTER DATABASE [$quoted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$quoted]; END; EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$escaped';"
            }
        }

        # NUL keeps the history and leaves no file. Two fulls, so a database has a chain of its own.
        $victimDb = "dbatoolsci_nvictim_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$victimDb]; BACKUP DATABASE [$victimDb] TO DISK = N'NUL'; BACKUP DATABASE [$victimDb] TO DISK = N'NUL';"
        $quoteDb = "dbatoolsci_o'hist_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$quoteDb]; BACKUP DATABASE [$quoteDb] TO DISK = N'NUL';"
        # A Chinese letter, outside every code page a lab collation uses, built by number: 5.1 reads this file as ANSI.
        $unicodeDb = "dbatoolsci_$([char]0x8BED)_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$unicodeDb]; BACKUP DATABASE [$unicodeDb] TO DISK = N'NUL';"
        $wildcardDb = "dbatoolsci_nwild_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$wildcardDb]; BACKUP DATABASE [$wildcardDb] TO DISK = N'NUL';"
        $wildcardPattern = "dbatoolsci_nwil*_$random"
        $noSizeDb = "dbatoolsci_nnosize_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$noSizeDb]; BACKUP DATABASE [$noSizeDb] TO DISK = N'NUL'; BACKUP DATABASE [$noSizeDb] TO DISK = N'NUL';"
        $chainDb = "dbatoolsci_nchain_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$chainDb]; ALTER DATABASE [$chainDb] SET RECOVERY FULL; BACKUP DATABASE [$chainDb] TO DISK = N'NUL'; BACKUP LOG [$chainDb] TO DISK = N'NUL'; BACKUP LOG [$chainDb] TO DISK = N'NUL' WITH COPY_ONLY;"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-NativeDatabase -Name $victimDb, $quoteDb, $unicodeDb, $wildcardDb, $noSizeDb, $chainDb
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "A -Last chain that cannot be completed" {
        It "ends -Last with the failure instead of a chain without its logs" {
            $whole = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $chainDb -Last -IncludeCopyOnly)
            $whole.Type | Should -Contain "Log"

            # DATEDIFF(SECOND) overflows past 68 years (Learn, DATEDIFF), so the statement that reads this row fails after the
            # one that read the full has succeeded. Only -IncludeCopyOnly reads a copy-only row and the row is mended at once,
            # so the other leg's whole-instance reads of this shared msdb never reach it.
            $copyLog = (Invoke-NativeSql "SELECT backup_set_id FROM msdb.dbo.backupset WHERE database_name = N'$chainDb' AND type = 'L' AND is_copy_only = 1").backup_set_id
            $failure = $null
            try {
                $null = Invoke-NativeSql "UPDATE msdb.dbo.backupset SET backup_start_date = '19000101' WHERE backup_set_id = $copyLog;"
                $full = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $chainDb -LastFull -IncludeCopyOnly)
                $chain = @(try { Get-DbaDbBackupHistory -SqlInstance $instance -Database $chainDb -Last -IncludeCopyOnly -ErrorAction SilentlyContinue } catch { $failure = $_ })
            } finally {
                $null = Invoke-NativeSql "UPDATE msdb.dbo.backupset SET backup_start_date = backup_finish_date WHERE backup_set_id = $copyLog;"
            }

            $full.Count | Should -Be 1
            $chain.Count | Should -Be 0
            $failure.FullyQualifiedErrorId | Should -BeLike "ExecutionFailureException*"
            $failure.Exception.Message | Should -BeLike 'Exception calling "ExecuteWithResults" with "1" argument(s): *'
            $failure.Exception.GetBaseException().Message | Should -BeLike "*datediff*"
        }
    }

    Context "A history row with no compressed size" {
        It "reports a backup with no compressed size as uncompressed" {
            # Learn, backupset: during an msdb upgrade this value is set to NULL, which indicates an uncompressed backup.
            $oldest = (Invoke-NativeSql "SELECT MIN(backup_set_id) AS id FROM msdb.dbo.backupset WHERE database_name = N'$noSizeDb'").id
            $null = Invoke-NativeSql "UPDATE msdb.dbo.backupset SET compressed_backup_size = NULL WHERE backup_set_id = $oldest;"
            $result = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $noSizeDb)
            $result.Count | Should -Be 2
            $newest = $result | Where-Object BackupSetId -ne "$oldest"
            $uncompressed = $result | Where-Object BackupSetId -eq "$oldest"
            $newest.CompressedBackupSize.Byte | Should -BeGreaterThan 0
            $uncompressed.CompressedBackupSize | Should -BeNullOrEmpty
            $uncompressed.CompressionRatio | Should -Be 1
            $uncompressed.TotalSize.Byte | Should -BeGreaterThan 0
        }
    }

    Context "Caller text stays text" {
        It "passes a -Database name as text, never as SQL" {
            $injected = "nosuch') OR database_name = N'$victimDb' --"
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $injected -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It "passes a -Database name as text under -LastFull, never as SQL" {
            $injected = "nosuch' OR database_name = N'$victimDb' --"
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $injected -LastFull -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It "passes a -DeviceType value as text, never as SQL" {
            $injected = "2') OR database_name = N'$victimDb' --"
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database nosuch -DeviceType $injected -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It "finds a database with a quote in its name" {
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $quoteDb -ErrorAction SilentlyContinue).Database | Should -Be $quoteDb
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $quoteDb -LastFull -ErrorAction SilentlyContinue).Database | Should -Be $quoteDb
        }
    }

    Context "Unicode database names" {
        It "finds a database whose name its code page cannot hold" {
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $unicodeDb).Database | Should -Be $unicodeDb
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $unicodeDb -LastFull).Database | Should -Be $unicodeDb
        }
    }

    Context "Wildcards in -Database" {
        It "expands a wildcard in -Database" {
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $wildcardPattern).Database | Should -Be $wildcardDb
        }

        It "expands a wildcard in -Database under -LastFull" {
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $wildcardPattern -LastFull).Database | Should -Be $wildcardDb
        }

        It "expands a wildcard in -Database under -Last" {
            @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $wildcardPattern -Last).Database | Should -Be $wildcardDb
        }
    }
}

# The pin passes each result set through Group-Object, which sorts its groups on PowerShell 7 and keeps first-occurrence
# order on Windows PowerShell 5.1 (https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell).
Describe "Native Get-DbaDbBackupHistory grouped output order" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance

        function Invoke-NativeSql {
            param([string]$Sql)
            $server.Query($Sql)
        }

        $orderDb = "dbatoolsci_norder_$random"
        $otherDb = "dbatoolsci_nordertwo_$random"
        $null = Invoke-NativeSql "CREATE DATABASE [$orderDb]; ALTER DATABASE [$orderDb] SET RECOVERY FULL; CREATE DATABASE [$otherDb];"
        $null = Invoke-NativeSql "CREATE TABLE [$orderDb].dbo.history (x int);"

        # backup_set_id is the identity of msdb.dbo.backupset. It moves to just under a power of ten, so these backup
        # sets gain a digit and their numeric order differs from their text order. AfterAll moves it back.
        $identityBefore = [long](Invoke-NativeSql "EXEC msdb.sys.sp_executesql N'SELECT CONVERT(bigint, IDENT_CURRENT(''dbo.backupset'')) AS id;';").id
        $power = [long]10
        while ($power -le ($identityBefore + 1)) {
            $power *= 10
        }
        $reseed = [Math]::Max($identityBefore, $power - 3)
        $null = Invoke-NativeSql "DBCC CHECKIDENT ('msdb.dbo.backupset', RESEED, $reseed) WITH NO_INFOMSGS;"

        # NUL keeps the history and leaves no file. Each row moves the log, so last_lsn orders these backup sets.
        $null = Invoke-NativeSql "BACKUP DATABASE [$orderDb] TO DISK = N'NUL';"
        $null = Invoke-NativeSql "INSERT [$orderDb].dbo.history VALUES (1);"
        $null = Invoke-NativeSql "BACKUP DATABASE [$orderDb] TO DISK = N'NUL' WITH DIFFERENTIAL;"
        $null = Invoke-NativeSql "INSERT [$orderDb].dbo.history VALUES (2);"
        $null = Invoke-NativeSql "BACKUP LOG [$orderDb] TO DISK = N'NUL';"
        $null = Invoke-NativeSql "INSERT [$orderDb].dbo.history VALUES (3);"
        $null = Invoke-NativeSql "BACKUP LOG [$orderDb] TO DISK = N'NUL';"
        $null = Invoke-NativeSql "BACKUP DATABASE [$otherDb] TO DISK = N'NUL';"

        # The same history read independently of the command: the query order, then the numeric order.
        $queryOrder = @((Invoke-NativeSql "SELECT backup_set_id FROM msdb.dbo.backupset WHERE database_name = N'$orderDb' ORDER BY last_lsn DESC").backup_set_id | ForEach-Object { [long]$PSItem })
        $numericOrder = @($queryOrder | Sort-Object)
        $otherFull = [long](Invoke-NativeSql "SELECT backup_set_id FROM msdb.dbo.backupset WHERE database_name = N'$otherDb'").backup_set_id

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $orderDb, $otherDb) {
            $null = Invoke-NativeSql "IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END; EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$name';"
        }
        if ($null -ne $identityBefore) {
            $null = Invoke-NativeSql "IF NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset WHERE backup_set_id > $identityBefore) DBCC CHECKIDENT ('msdb.dbo.backupset', RESEED, $identityBefore) WITH NO_INFOMSGS;"
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "works on backup sets whose ids gain a digit" {
        $queryOrder.Count | Should -Be 4
        "$($numericOrder[0])".Length | Should -BeLessThan "$($numericOrder[-1])".Length
    }

    It "emits the groups of one result set by ascending BackupSetId on PowerShell 7 and in query order on Windows PowerShell" {
        $expected = if ($PSVersionTable.PSEdition -eq "Core") { $numericOrder } else { $queryOrder }
        $results = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $orderDb)
        ($results.BackupSetId -join ",") | Should -Be ($expected -join ",")
    }

    It "sorts one -LastFull result set over two databases the same way" {
        $orderFull = $numericOrder[0]
        $expected = if ($PSVersionTable.PSEdition -eq "Core") { $orderFull, $otherFull } else { $otherFull, $orderFull }
        $results = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $otherDb, $orderDb -LastFull)
        ($results.BackupSetId -join ",") | Should -Be ($expected -join ",")
    }

    It "keeps query order under -Raw on both editions" {
        $results = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $orderDb -Raw)
        ($results.BackupSetId -join ",") | Should -Be ($queryOrder -join ",")
    }

    It "keeps the -Last chain in LSN order on both editions" {
        $results = @(Get-DbaDbBackupHistory -SqlInstance $instance -Database $orderDb -Last)
        ($results.BackupSetId -join ",") | Should -Be ($numericOrder -join ",")
    }
}

Describe "Native Get-DbaDbBackupHistory refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") {
                        $isResuming = $true
                    }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaDbBackupHistory @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaDbBackupHistory -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
    }
}
