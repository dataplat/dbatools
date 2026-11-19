#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbEncryptionKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads $db.DatabaseEncryptionKey.

Describe "Get-DbaDbEncryptionKey native" -Tag IntegrationTests {
    BeforeAll {
        # CREATE DATABASE ENCRYPTION KEY needs a certificate in master under master's database master key. A run that creates the
        # master key also creates the fixed-name mark certificate under it, so the key itself records that a run of this test made
        # it. Every run's cleanup drops the mark and the key once the mark is the only private key in master the key protects, so
        # the last run to finish removes the key whichever run created it, and a master key that was there before (no mark) stays.
        # Both helpers hold one session application lock in master, so another run on the same instance (the SQL login instance
        # is shared by every leg) never sees the key between its own check and its own certificate, or loses it while its
        # certificate is made.
        function Get-MasterKeyCleanup {
            @"
IF CERT_ID(N'dbatools_native_dek_master_key_mark') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.certificates WHERE pvt_key_encryption_type = N'MK' AND name <> N'dbatools_native_dek_master_key_mark') AND NOT EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE pvt_key_encryption_type = N'MK')
BEGIN
    DROP CERTIFICATE [dbatools_native_dek_master_key_mark];
    DROP MASTER KEY;
END
"@
        }

        function New-MasterCertificate {
            param($Target, [string]$Name)
            $masterKeyLock = "N'dbatools-native-dek-master-key'"
            $password = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
            $masterDatabase = $Target.Databases["master"]
            $batch = @"
DECLARE @lock int;
EXEC @lock = sp_getapplock @Resource = $masterKeyLock, @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = 120000;
IF @lock < 0 THROW 50000, N'The native test could not take its master key lock.', 1;
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    BEGIN
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$password';
        CREATE CERTIFICATE [dbatools_native_dek_master_key_mark] WITH SUBJECT = N'dbatools native test master key mark';
    END
    CREATE CERTIFICATE [$Name] WITH SUBJECT = N'dbatools native test';
    EXEC sp_releaseapplock @Resource = $masterKeyLock, @LockOwner = N'Session';
END TRY
BEGIN CATCH
    $(Get-MasterKeyCleanup)
    EXEC sp_releaseapplock @Resource = $masterKeyLock, @LockOwner = N'Session';
    THROW;
END CATCH
"@
            $null = $masterDatabase.ExecuteNonQuery($batch)
        }

        function New-KeyedDatabase {
            param($Target, [string]$Name, [string]$Algorithm, [string]$Certificate)
            $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Target, $Name
            $database.Create()
            $database.ExecuteNonQuery("CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = $Algorithm ENCRYPTION BY SERVER CERTIFICATE [$Certificate];")
            $database
        }

        # One batch on one session, which also ends the command's pooled connections, and the engine's own message if it fails.
        # A background task can hold a database for a moment, so the drop gets a few tries.
        function Remove-NativeDatabase {
            param($Target, [string]$Name)
            if ($Name -notin @($Target.Query("SELECT name FROM sys.databases")).name) {
                return
            }
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    $null = $Target.ConnectionContext.ExecuteNonQuery("USE master; ALTER DATABASE [$Name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Name];")
                    return
                } catch {
                    if ($attempt -eq 5) { throw }
                    Start-Sleep -Seconds 2
                }
            }
        }

        # The certificate goes once no key uses it, then the marked master key once no other private key in master is protected
        # by it (Get-MasterKeyCleanup), so another run's certificate keeps its key and the last run drops it.
        function Remove-KeyedDatabase {
            param($Target, [string[]]$Name, [string]$Certificate)
            foreach ($dbName in $Name) {
                Remove-NativeDatabase -Target $Target -Name $dbName
            }
            $masterKeyLock = "N'dbatools-native-dek-master-key'"
            $batch = @"
DECLARE @lock int;
EXEC @lock = sp_getapplock @Resource = $masterKeyLock, @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = 120000;
IF @lock < 0 THROW 50000, N'The native test could not take its master key lock.', 1;
BEGIN TRY
    IF CERT_ID(N'$Certificate') IS NOT NULL DROP CERTIFICATE [$Certificate];
    $(Get-MasterKeyCleanup)
    EXEC sp_releaseapplock @Resource = $masterKeyLock, @LockOwner = N'Session';
END TRY
BEGIN CATCH
    EXEC sp_releaseapplock @Resource = $masterKeyLock, @LockOwner = N'Session';
    THROW;
END CATCH
"@
            $Target.Databases["master"].ExecuteNonQuery($batch)
        }

        # Unique per leg and run (lane-safe); AfterAll drops the databases, the certificate and, as the last user, a marked master key.
        $prefix = "native_dek_" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $certName = "${prefix}_cert"
        $dbNameA = "${prefix}_a"
        $dbNameB = "${prefix}_b"
        $dbNameC = "${prefix}_c"
        $dbNameNone = "${prefix}_none"
        New-MasterCertificate -Target $server -Name $certName
        $databaseA = New-KeyedDatabase -Target $server -Name $dbNameA -Algorithm AES_256 -Certificate $certName
        $databaseB = New-KeyedDatabase -Target $server -Name $dbNameB -Algorithm AES_128 -Certificate $certName
        $databaseC = New-KeyedDatabase -Target $server -Name $dbNameC -Algorithm AES_192 -Certificate $certName
        $databaseNone = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbNameNone
        $databaseNone.Create()
        $badInstance = "TCP:127.0.0.1,1"
        $displaySet = @("ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "EncryptionAlgorithm", "EncryptionState", "EncryptionType", "EncryptorName", "ModifyDate", "OpenedDate", "RegenerateDate", "SetDate", "Thumbprint")
    }

    AfterAll {
        Remove-KeyedDatabase -Target $server -Name $dbNameA, $dbNameB, $dbNameC, $dbNameNone -Certificate $certName
    }

    Context "Keys and filters" {
        It "returns the key as a decorated SMO key with the pinned default view" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey
            $result.ComputerName | Should -BeExactly $server.ComputerName
            $result.InstanceName | Should -BeExactly $server.ServiceName
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.Database | Should -BeExactly $dbNameA
            $result.EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
            $result.EncryptionType.ToString() | Should -BeExactly "ServerCertificate"
            $result.EncryptorName | Should -BeExactly $certName
            [int]$result.EncryptionState | Should -Be 1
            $result.CreateDate | Should -BeOfType System.DateTime
            $thumbprint = @($server.Query("SELECT thumbprint FROM master.sys.certificates WHERE name = N'$certName'"))[0].thumbprint
            ($result.Thumbprint -join ",") | Should -BeExactly ($thumbprint -join ",")
            @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $displaySet
        }

        It "reports a key created with AES_128" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameB -EnableException)
            $results.Count | Should -Be 1
            $results[0].Database | Should -BeExactly $dbNameB
            $results[0].EncryptionAlgorithm.ToString() | Should -BeExactly "Aes128"
        }

        It "returns the key of every selected database" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameC -EnableException)
            ($results.Database | Sort-Object) | Should -Be @($dbNameA, $dbNameC)
            ($results | Where-Object Database -eq $dbNameC).EncryptionAlgorithm.ToString() | Should -BeExactly "Aes192"
        }

        It "excludes a database by name" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameC -ExcludeDatabase $dbNameA -EnableException)
            $results.Database | Should -BeExactly $dbNameC
        }

        It "returns nothing and warns nothing for a database with no key" {
            $noKeyWarnings = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameNone -WarningVariable noKeyWarnings)
            $results.Count | Should -Be 0
            $noKeyWarnings.Count | Should -Be 0
        }

        It "matches -Database wildcards, as the help documents" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database "${prefix}_?" -EnableException)
            ($results.Database | Sort-Object) | Should -Be @($dbNameA, $dbNameB, $dbNameC)
        }

        It "compares -ExcludeDatabase exactly, as its help documents no wildcards" {
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameC -ExcludeDatabase "*_a" -EnableException)
            ($results.Database | Sort-Object) | Should -Be @($dbNameA, $dbNameC)
        }
    }

    Context "Piped databases" {
        It "reads every piped database" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameC, $dbNameNone | Get-DbaDbEncryptionKey -EnableException)
            ($results.Database | Sort-Object) | Should -Be @($dbNameA, $dbNameC)
            foreach ($result in $results) {
                $result.ComputerName | Should -BeExactly $server.ComputerName
                $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            }
        }

        It "reads a command-line -SqlInstance once across piped databases" {
            $pipedDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA
            $results = @(@($pipedDatabase, $pipedDatabase) | Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameC -EnableException)
            $results.Database | Should -Be @($dbNameA, $dbNameC, $dbNameA)
        }

        It "reports the instance of a database piped straight from SMO" {
            $rawServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            try {
                $rawDatabase = $rawServer.Databases[$dbNameC]
                $rawDatabase.PSObject.Properties["SqlInstance"] | Should -BeNullOrEmpty
                $results = @($rawDatabase | Get-DbaDbEncryptionKey -EnableException)
                $results.Database | Should -BeExactly $dbNameC
                $results[0].ComputerName | Should -BeExactly $rawServer.ComputerName
                $results[0].InstanceName | Should -BeExactly $rawServer.ServiceName
                $results[0].SqlInstance | Should -BeExactly $rawServer.DomainInstanceName
            } finally {
                $rawServer.ConnectionContext.Disconnect()
            }
        }
    }

    Context "A key read that is refused" {
        BeforeAll {
            $refusedLogin = "${prefix}_refused"
            $refusedPassword = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
            $null = $server.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$refusedLogin] WITH PASSWORD = N'$refusedPassword', CHECK_POLICY = OFF;")
        }

        AfterAll {
            $null = $server.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$refusedLogin];")
        }

        # sys.dm_database_encryption_keys needs VIEW SERVER STATE, or VIEW SERVER SECURITY STATE from SQL Server 2022, which this
        # login lacks. The key is still there, so "no key" would be a false answer.
        It "reports a key read it was refused, not a missing key" {
            $refusedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            try {
                # Enumerating fills the collection as the connection's own login, so the database stays accessible afterwards.
                @($refusedServer.Databases | Where-Object { $PSItem.Name -eq $dbNameA -and $PSItem.IsAccessible }).Count | Should -Be 1
                $refusedDatabase = $refusedServer.Databases[$dbNameA]
                $null = $refusedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS LOGIN = N'$refusedLogin';")

                $refusedWarnings = @()
                $results = @($refusedDatabase | Get-DbaDbEncryptionKey -WarningVariable refusedWarnings -WarningAction SilentlyContinue)
                $results.Count | Should -Be 0
                ($refusedWarnings -join " ") | Should -BeLike "*Failure reading the encryption key of the *$dbNameA* database*"
                { $refusedDatabase | Get-DbaDbEncryptionKey -EnableException -WarningAction SilentlyContinue } | Should -Throw
            } finally {
                $null = $refusedServer | Disconnect-DbaInstance
            }
        }
    }

    Context "A database that is not accessible" {
        It "warns and goes on to the next database" {
            $offlineName = "${prefix}_offline"
            $offlineDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $offlineName
            $offlineDatabase.Create()
            try {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
                $offlineWarnings = @()
                $results = @(Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $dbNameC -WarningVariable offlineWarnings -WarningAction SilentlyContinue)
                $results.Database | Should -BeExactly $dbNameC
                ($offlineWarnings -join " ") | Should -Match ([regex]::Escape("[$offlineName] is not accessible, skipping"))
            } finally {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET ONLINE;")
                Remove-NativeDatabase -Target $server -Name $offlineName
            }
        }
    }

    Context "Connection failures" {
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbEncryptionKey.ps1, the process block:
        #         if ($SqlInstance) {
        #             $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        #         }
        #
        # -EnableException never reaches the nested Get-DbaDatabase, whose Stop-Function warns "Failure" and moves on, so the
        # command warns and reads the next instance with or without the switch, and never throws here.
        # The caller's -ErrorVariable holds the nested Get-DbaDatabase Stop-Function record in each form, as the pinned nested call
        # puts it there (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the caught Connect-DbaInstance
        # records and blank entries: accepted difference omitted-consequential-records.
        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $connectErrors = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameC -WarningVariable connectWarnings -WarningAction SilentlyContinue -ErrorVariable connectErrors)
            ($connectWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Database | Should -BeExactly $dbNameC
            $connectErrors = @($connectErrors)
            $connectErrors.Count | Should -Be 1
            $connectErrors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $connectErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
            "$($connectErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $connectErrors[0].Exception.Message | Should -Not -BeNullOrEmpty
            $connectErrors[0].Exception.InnerException | Should -Not -BeNullOrEmpty
        }

        It "warns the same under -EnableException, which the nested Get-DbaDatabase never gets" -Tag NativeChecklist:enable-exception {
            $enabledWarnings = @()
            $enabledErrors = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameC -EnableException -WarningVariable enabledWarnings -WarningAction SilentlyContinue -ErrorVariable enabledErrors)
            ($enabledWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Database | Should -BeExactly $dbNameC
            @($enabledErrors).Count | Should -Be 1
            @($enabledErrors)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $falseErrors = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameC -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue -ErrorVariable falseErrors)
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Database | Should -BeExactly $dbNameC
            @($falseErrors).Count | Should -Be 1
            @($falseErrors)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            New-MasterCertificate -Target $loginServer -Name $certName
            $null = New-KeyedDatabase -Target $loginServer -Name $loginDbName -Algorithm AES_256 -Certificate $certName
        }

        AfterAll {
            if ($loginServer) {
                Remove-KeyedDatabase -Target $loginServer -Name $loginDbName -Certificate $certName
            }
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Database | Should -BeExactly $loginDbName
            $results.EncryptorName | Should -BeExactly $certName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        # The nested Get-DbaDatabase gets no -EnableException (see "Connection failures"): a warning, no output, no throw.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $noLoginEnabledWarnings = @()
            $results = @(Get-DbaDbEncryptionKey -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningVariable noLoginEnabledWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginEnabledWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}

Describe "Get-DbaDbEncryptionKey native on Azure SQL Database" -Tag IntegrationTests {
    # sys.dm_database_encryption_keys applies to Azure SQL Database, where transparent data encryption is on by default
    # (https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-database-encryption-keys-transact-sql).
    It "reads the database encryption key of an Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once.
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
        try {
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $engineRows = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT encryption_state, create_date, key_algorithm, key_length, encryptor_thumbprint, encryptor_type FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID();").Tables[0].Rows)
            $engineRows.Count | Should -Be 1 -Because "the engine's own view shows this database's key"
            $splatAzureKey = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbEncryptionKey @splatAzureKey)
            $azureRows.Count | Should -Be 1 -Because "the command reports the key that view shows"
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $azureRows[0].EncryptionAlgorithm.ToString() | Should -BeExactly "Aes$($engineRows[0].key_length)"
            [int]$azureRows[0].EncryptionState | Should -Be $engineRows[0].encryption_state
            $azureRows[0].CreateDate | Should -Be $engineRows[0].create_date
            ($azureRows[0].Thumbprint -join ",") | Should -BeExactly ($engineRows[0].encryptor_thumbprint -join ",")
            $expectedType = if ($engineRows[0].encryptor_type -like "CERTIFICATE*") { "ServerCertificate" } else { "ServerAsymmetricKey" }
            $azureRows[0].EncryptionType.ToString() | Should -BeExactly $expectedType
            $azureRows[0].EncryptorName | Should -BeNullOrEmpty
            $azureDisplaySet = @("ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "EncryptionAlgorithm", "EncryptionState", "EncryptionType", "EncryptorName", "ModifyDate", "OpenedDate", "RegenerateDate", "SetDate", "Thumbprint")
            @($azureRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $azureDisplaySet
        } finally {
            $azureServer.ConnectionContext.Disconnect()
        }
    }
}
