#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbRecoveryModel",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads databases.

Describe "Native Get-DbaDbRecoveryModel" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run; AfterAll drops them. They are created out of name order, so the order of sys.databases is not the
        # order of their names.
        $suffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $dbFull = "dbatoolsci_rm_z_full_$suffix"
        $dbBulk = "dbatoolsci_rm_a_bulk_$suffix"
        $dbSimple = "dbatoolsci_rm_m_simple_$suffix"
        $dbOffline = "dbatoolsci_rm_c_offline_$suffix"
        $own = $dbFull, $dbBulk, $dbSimple, $dbOffline
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # The query Get-DbaDatabase runs, whose rows set the order of the output.
        $rawQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases"
        $modelQuery = "SELECT name, recovery_model_desc FROM sys.databases"
        $modelNames = @{ FULL = "Full"; BULK_LOGGED = "BulkLogged"; SIMPLE = "Simple" }
        $view = "ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsAccessible", "RecoveryModel", "LastFullBackup", "LastDiffBackup", "LastLogBackup"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $null = $server.Query("CREATE DATABASE [$dbFull]; ALTER DATABASE [$dbFull] SET RECOVERY FULL;")
        $null = $server.Query("CREATE DATABASE [$dbBulk]; ALTER DATABASE [$dbBulk] SET RECOVERY BULK_LOGGED;")
        $null = $server.Query("CREATE DATABASE [$dbSimple]; ALTER DATABASE [$dbSimple] SET RECOVERY SIMPLE;")
        $null = $server.Query("CREATE DATABASE [$dbOffline]; ALTER DATABASE [$dbOffline] SET RECOVERY FULL;")
        $null = $server.Query("ALTER DATABASE [$dbOffline] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        # The tests pass this connection too, and SMO keeps the list of databases it read before they were created.
        $server.Databases.Refresh()

        $splatRead = @{
            SqlInstance     = $TestConfig.InstanceSingle
            EnableException = $true
        }
    }

    AfterAll {
        # Each database on its own, so that one failure leaves the next to drop.
        foreach ($dbName in $own) {
            try {
                $null = $server.Query("IF DB_ID(N'$dbName') IS NOT NULL ALTER DATABASE [$dbName] SET ONLINE;")
                $null = $server.Query("IF DB_ID(N'$dbName') IS NOT NULL BEGIN ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbName]; END;")
            } catch {
                Write-Warning "Cleanup of ${dbName}: $PSItem"
            }
        }
    }

    It "returns each database with the pinned default view and the members Get-DbaDatabase adds" {
        $rows = @(Get-DbaDbRecoveryModel @splatRead -Database $dbFull)
        $rows.Count | Should -Be 1
        $row = $rows[0]
        $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
        $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly $view
        $row.Name | Should -BeExactly $dbFull
        $row.SqlInstance | Should -BeExactly $server.DomainInstanceName
        $row.InstanceName | Should -BeExactly $server.ServiceName
        $row.ComputerName | Should -BeExactly $server.ComputerName
        foreach ($alias in @{ LastFullBackup = "LastBackupDate"; LastDiffBackup = "LastDifferentialBackupDate"; LastLogBackup = "LastLogBackupDate"; SizeMB = "Size"; Compatibility = "CompatibilityLevel"; Encrypted = "EncryptionEnabled" }.GetEnumerator()) {
            $member = Get-Member -InputObject $row -Name $alias.Key
            $member.MemberType | Should -Be "AliasProperty" -Because $alias.Key
            $member.Definition | Should -BeLike "*= $($alias.Value)" -Because $alias.Key
        }
        foreach ($note in "BackupStatus", "LastRead", "LastWrite", "IsCdcEnabled", "ComputerName", "InstanceName", "SqlInstance") {
            (Get-Member -InputObject $row -Name $note).MemberType | Should -Be "NoteProperty" -Because $note
        }
        $row.BackupStatus | Should -BeNullOrEmpty
        $row.LastRead | Should -BeNullOrEmpty
        $row.LastWrite | Should -BeNullOrEmpty
        $row.IsCdcEnabled | Should -BeExactly (@($server.Query($rawQuery) | Where-Object name -eq $dbFull)[0].is_cdc_enabled)
    }

    It "reports each recovery model as sys.databases does" {
        $expected = @{ }
        foreach ($modelRow in @($server.Query($modelQuery))) {
            $expected[$modelRow.name] = $modelNames[$modelRow.recovery_model_desc]
        }
        $rows = @(Get-DbaDbRecoveryModel @splatRead -Database $own)
        $rows.Count | Should -Be 4
        foreach ($row in $rows) {
            "$($row.RecoveryModel)" | Should -BeExactly $expected[$row.Name] -Because $row.Name
        }
        @($rows | Where-Object Name -eq $dbBulk)[0].RecoveryModel | Should -Be "BulkLogged"
    }

    It "writes the databases in the order sys.databases gives" {
        $expected = @($server.Query($rawQuery) | Where-Object name -in $own | ForEach-Object name)
        $expected.Count | Should -Be 4
        @(Get-DbaDbRecoveryModel @splatRead -Database $dbSimple, $dbOffline, $dbBulk, $dbFull).Name | Should -BeExactly $expected
    }

    It "lists an offline database, and leaves it out under -RecoveryModel" {
        $rows = @(Get-DbaDbRecoveryModel @splatRead -Database $dbOffline)
        $rows.Count | Should -Be 1
        $rows[0].IsAccessible | Should -BeFalse
        "$($rows[0].Status)" | Should -Match "Offline"
        @(Get-DbaDbRecoveryModel @splatRead -Database $own -RecoveryModel Full).Name | Should -BeExactly @($dbFull)
    }

    It "keeps the databases of each model -RecoveryModel names, in any case" {
        $expected = @($server.Query($rawQuery) | Where-Object name -in $dbFull, $dbBulk | ForEach-Object name)
        @(Get-DbaDbRecoveryModel @splatRead -Database $own -RecoveryModel Full, BulkLogged).Name | Should -BeExactly $expected
        @(Get-DbaDbRecoveryModel @splatRead -Database $own -RecoveryModel simple).Name | Should -BeExactly @($dbSimple)
        @(Get-DbaDbRecoveryModel @splatRead -Database $dbFull -RecoveryModel Simple).Count | Should -Be 0
    }

    It "matches -Database and -ExcludeDatabase in any case" {
        @(Get-DbaDbRecoveryModel @splatRead -Database $dbFull.ToUpperInvariant()).Name | Should -BeExactly @($dbFull)
        @(Get-DbaDbRecoveryModel @splatRead -Database $dbFull, $dbBulk -ExcludeDatabase $dbFull.ToUpperInvariant()).Name | Should -BeExactly @($dbBulk)
    }

    It "reads every database for an empty -Database" {
        $expected = @(Get-DbaDbRecoveryModel @splatRead).Name
        $expected | Should -Contain $dbFull
        foreach ($form in @(@{ Database = "" }, @{ Database = $null }, @{ Database = @() })) {
            @(Get-DbaDbRecoveryModel @splatRead @form).Name | Should -BeExactly $expected
        }
    }

    # Correction database-wildcards: the pinned help documents wildcards for -Database, which Get-DbaDatabase compared exactly.
    It "reads the databases a wildcard -Database names" {
        $expected = @($server.Query($rawQuery) | Where-Object name -in $own | ForEach-Object name)
        @(Get-DbaDbRecoveryModel @splatRead -Database "dbatoolsci_rm_*_$suffix").Name | Should -BeExactly $expected
        @(Get-DbaDbRecoveryModel @splatRead -Database "DBATOOLSCI_RM_?_FULL_$suffix").Name | Should -BeExactly @($dbFull)
    }

    # Correction database-wildcards: the pinned help documents wildcards for -ExcludeDatabase, which Get-DbaDatabase compared exactly.
    It "leaves out the databases a wildcard -ExcludeDatabase names" {
        $expected = @($server.Query($rawQuery) | Where-Object name -in $dbFull, $dbBulk | ForEach-Object name)
        @(Get-DbaDbRecoveryModel @splatRead -Database $own -ExcludeDatabase "dbatoolsci_rm_?_*e_$suffix").Name | Should -BeExactly $expected
        @(Get-DbaDbRecoveryModel @splatRead -ExcludeDatabase "dbatoolsci_rm_*_$suffix").Name | Should -Not -Contain $dbFull
    }

    It "takes a connected server" {
        @(Get-DbaDbRecoveryModel -SqlInstance $server -Database $dbFull -EnableException).Name | Should -BeExactly @($dbFull)
    }

    It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
        $rows = @($TestConfig.InstanceSingle, $server | Get-DbaDbRecoveryModel -Database $dbFull -EnableException)
        $rows.Count | Should -Be 2
        $rows.Name | Should -BeExactly @($dbFull, $dbFull)
    }

    # The warning stream, not -WarningVariable: a nested warning lands there more than once. Matched on Get-DbaDatabase's warning, not
    # counted: the pinned Connect-DbaInstance warns as well, which the shared connection helper does not repeat.
    It "warns under Get-DbaDatabase's name for an instance it cannot reach, then reads the next" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $stream = @(Get-DbaDbRecoveryModel -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbFull -EnableException:$false 3>&1)
        $warnings = @($stream | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] })
        @($warnings | Where-Object { "$PSItem" -like "*Get-DbaDatabase*Failure | *" }).Count | Should -Be 1
        @($stream | Where-Object { $PSItem -isnot [System.Management.Automation.WarningRecord] }).Name | Should -BeExactly @($dbFull)
    }

    # The pinned command passes -EnableException on to Get-DbaDatabase, whose Stop-Function -Continue then throws.
    It "throws Get-DbaDatabase's record under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $rows = @()
        $failure = $null
        try {
            $rows = @(Get-DbaDbRecoveryModel -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbFull -EnableException -WarningAction SilentlyContinue)
        } catch {
            $failure = $PSItem
        }
        $rows.Count | Should -Be 0
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        $failure.CategoryInfo.Category | Should -Be "ConnectionError"
        "$($failure.TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
        $chain = @()
        for ($inner = $failure.Exception.InnerException; $null -ne $inner; $inner = $inner.InnerException) {
            $chain += $inner.GetType().FullName
        }
        $chain | Should -Contain "Microsoft.Data.SqlClient.SqlException"
    }
}

Describe "Native Get-DbaDbRecoveryModel over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $rows = @(Get-DbaDbRecoveryModel -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -EnableException)
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -BeExactly "master"
            $rows[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
            "$($rows[0].RecoveryModel)" | Should -BeExactly "Simple"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginStream = @(Get-DbaDbRecoveryModel -SqlInstance $loginInstance -EnableException:$false 3>&1)
            @($loginStream | Where-Object { $PSItem -isnot [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
            @($loginStream | Where-Object { "$PSItem" -like "*Get-DbaDatabase*Failure | *Login failed*" }).Count | Should -Be 1
        }

        It "throws without the credential under -EnableException" {
            { Get-DbaDbRecoveryModel -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Login failed*"
        }
    }
}

Describe "Native Get-DbaDbRecoveryModel on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001 -or $azureError.Message -like "*No such host is known*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # azure-sqldb: the command works there, read-only, so the six legs can share the database. LastFullBackup, LastDiffBackup and
    # LastLogBackup stay as SMO reports them on Azure SQL Database, with no new error or warning (delegated decision, watchman
    # 6d01035131af6c9c): sys.dm_database_backups reports service-managed automatic backups, not the msdb history these properties
    # read, so filling them would change their meaning on one platform. No test here presents that as a wanted outcome; it is a
    # follow-up for Get-DbaDatabase's conversion, which writes the same object.
    It "reads an Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $rows = @(Get-DbaDbRecoveryModel -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly $TestConfig.AzureSqlDbName
        $rows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $rows[0].IsAccessible | Should -BeTrue
        "$($rows[0].Status)" | Should -Match "Normal"
        $rows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Contain "RecoveryModel"
    }

    # Correction azure-recovery-model: SMO's getter fails on Azure SQL Database, where sys.databases reports the model.
    It "reads the recovery model of an Azure SQL Database as sys.databases reports it" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $expected = @($azureServer.Query("SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME();"))[0].recovery_model_desc
        $rows = @(Get-DbaDbRecoveryModel -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly $TestConfig.AzureSqlDbName
        "$($rows[0].RecoveryModel)".ToUpperInvariant() | Should -BeExactly $expected
        @(Get-DbaDbRecoveryModel -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -RecoveryModel Full -EnableException).Name | Should -BeExactly @($TestConfig.AzureSqlDbName)
    }
}
