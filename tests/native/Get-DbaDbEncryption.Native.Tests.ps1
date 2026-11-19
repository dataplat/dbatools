#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads encryption objects.

Describe "Get-DbaDbEncryption native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run (lane-safe); AfterAll drops all of it.
        $prefix = "native_encryption_" + [Guid]::NewGuid().ToString("N")
        $password = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dbNameA = "${prefix}_a"
        $dbNameB = "${prefix}_b"
        $certificateNameA = "${prefix}_cert_a"
        $certificateNameB = "${prefix}_cert_b"
        $asymmetricName = "${prefix}_asym"
        $symmetricName = "${prefix}_sym"
        $databaseA = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbNameA
        $databaseA.Create()
        $databaseB = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbNameB
        $databaseB.Create()
        $databaseA.ExecuteNonQuery("CREATE CERTIFICATE [$certificateNameA] ENCRYPTION BY PASSWORD = N'$password' WITH SUBJECT = N'native';")
        $databaseA.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$asymmetricName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$password';")
        $databaseA.ExecuteNonQuery("CREATE SYMMETRIC KEY [$symmetricName] WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = N'$password';")
        $databaseB.ExecuteNonQuery("CREATE CERTIFICATE [$certificateNameB] ENCRYPTION BY PASSWORD = N'$password' WITH SUBJECT = N'native';")
        $badInstance = "TCP:127.0.0.1,1"
        $columns = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Encryption", "Name", "LastBackup", "PrivateKeyEncryptionType", "EncryptionAlgorithm", "KeyLength", "Owner", "Object", "ExpirationDate")
        $splatRead = @{
            SqlInstance     = $TestConfig.InstanceSingle
            EnableException = $true
        }
    }

    AfterAll {
        # KillDatabase ends the command's pooled connections before the drop.
        $server.Databases.Refresh()
        foreach ($dbName in @($dbNameA, $dbNameB)) {
            if ($server.Databases[$dbName]) {
                $server.KillDatabase($dbName)
            }
        }
    }

    Context "Rows of each kind" {
        BeforeAll {
            $rows = @(Get-DbaDbEncryption @splatRead -Database $dbNameA)
            $certificateRow = $rows | Where-Object Encryption -eq "Certificate"
            $asymmetricRow = $rows | Where-Object Encryption -eq "Asymmetric key"
            $symmetricRow = $rows | Where-Object Encryption -eq "Symmetric key"
        }

        It "returns the certificates, then the asymmetric keys, then the symmetric keys" {
            $rows.Encryption | Should -Be @("Certificate", "Asymmetric key", "Symmetric key")
            $rows.Name | Should -Be @($certificateNameA, $asymmetricName, $symmetricName)
            foreach ($row in $rows) {
                $row.PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
                $row.Database | Should -BeExactly $dbNameA
            }
        }

        It "returns a certificate row in the pinned column order" {
            @($certificateRow.PSObject.Properties.Name) | Should -Be $columns
            $certificateRow.ComputerName | Should -BeExactly $server.ComputerName
            $certificateRow.InstanceName | Should -BeExactly $server.ServiceName
            $certificateRow.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $certificateRow.Object | Should -BeOfType Microsoft.SqlServer.Management.Smo.Certificate
            $certificateRow.LastBackup | Should -Be $certificateRow.Object.LastBackupDate
            $certificateRow.ExpirationDate | Should -Be $certificateRow.Object.ExpirationDate
            $certificateRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
            $certificateRow.Owner | Should -BeExactly "dbo"
            $certificateRow.EncryptionAlgorithm | Should -BeNullOrEmpty
            $certificateRow.KeyLength | Should -BeNullOrEmpty
        }

        It "returns an asymmetric key row in the pinned column order" {
            @($asymmetricRow.PSObject.Properties.Name) | Should -Be $columns
            $asymmetricRow.Object | Should -BeOfType Microsoft.SqlServer.Management.Smo.AsymmetricKey
            $asymmetricRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
            $asymmetricRow.EncryptionAlgorithm.ToString() | Should -BeExactly "Rsa2048"
            $asymmetricRow.KeyLength | Should -Be 2048
            $asymmetricRow.Owner | Should -BeExactly "dbo"
            $asymmetricRow.LastBackup | Should -BeNullOrEmpty
            $asymmetricRow.ExpirationDate | Should -BeNullOrEmpty
        }

        It "returns a symmetric key row with its key length, owner and object" {
            $symmetricRow.Object | Should -BeOfType Microsoft.SqlServer.Management.Smo.SymmetricKey
            $symmetricRow.KeyLength | Should -Be 256
            $symmetricRow.Owner | Should -BeExactly "dbo"
            $symmetricRow.LastBackup | Should -BeNullOrEmpty
            $symmetricRow.ExpirationDate | Should -BeNullOrEmpty
        }

        It "keeps a symmetric key row's Server and Instance columns" {
            $symmetricRow.Server | Should -BeExactly $server.Name
            "$($symmetricRow.Instance)" | Should -BeExactly "$($server.InstanceName)"
        }

        It "gives a symmetric key row the documented instance columns" {
            $symmetricRow.ComputerName | Should -BeExactly $server.ComputerName
            $symmetricRow.InstanceName | Should -BeExactly $server.ServiceName
            $symmetricRow.SqlInstance | Should -BeExactly $server.DomainInstanceName
            @($symmetricRow.PSObject.Properties.Name) | Should -Be (@("ComputerName", "InstanceName", "SqlInstance", "Server", "Instance") + $columns[3..12])
        }

        It "reports a symmetric key's own algorithm" {
            $symmetricRow.EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
        }

        It "reports how a symmetric key is encrypted" {
            $symmetricRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
        }

        It "writes the database it is processing to the verbose stream" {
            $verboseRecords = @(Get-DbaDbEncryption @splatRead -Database $dbNameB -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] })
            ($verboseRecords.Message -join " ") | Should -Match ([regex]::Escape("Processing [$dbNameB]"))
        }
    }

    Context "Symmetric keys with other encryptions" {
        BeforeAll {
            $keysName = "${prefix}_keys"
            $keysCertificateName = "${prefix}_keys_cert"
            $byCertificateName = "${prefix}_by_certificate"
            $byBothName = "${prefix}_by_both"
            $keysDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $keysName
            $keysDatabase.Create()
            $keysDatabase.ExecuteNonQuery("CREATE CERTIFICATE [$keysCertificateName] ENCRYPTION BY PASSWORD = N'$password' WITH SUBJECT = N'native';")
            $keysDatabase.ExecuteNonQuery("CREATE SYMMETRIC KEY [$byCertificateName] WITH ALGORITHM = AES_128 ENCRYPTION BY CERTIFICATE [$keysCertificateName];")
            $keysDatabase.ExecuteNonQuery("CREATE SYMMETRIC KEY [$byBothName] WITH ALGORITHM = AES_128 ENCRYPTION BY PASSWORD = N'$password', CERTIFICATE [$keysCertificateName];")
        }

        AfterAll {
            $server.Databases.Refresh()
            if ($server.Databases[$keysName]) {
                $server.KillDatabase($keysName)
            }
        }

        It "reports the certificate that encrypts a symmetric key" {
            $rows = @(Get-DbaDbEncryption @splatRead -Database $keysName)
            ($rows | Where-Object Name -eq $byCertificateName).PrivateKeyEncryptionType.ToString() | Should -BeExactly "Certificate"
        }

        It "reports every encryption of a symmetric key, each filterable" {
            $rows = @(Get-DbaDbEncryption @splatRead -Database $keysName)
            $row = $rows | Where-Object Name -eq $byBothName
            @($row.PrivateKeyEncryptionType | ForEach-Object { $PSItem.ToString() }) | Should -Be @("Certificate", "Password")
            ($rows | Where-Object PrivateKeyEncryptionType -eq "Password").Name | Should -Contain $byBothName
        }
    }

    Context "A database that cannot be read" {
        BeforeAll {
            # Sorts ahead of the other databases, so the command has one left to go on to.
            $offlineName = "${prefix}_0offline"
            $offlineDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $offlineName
            $offlineDatabase.Create()
            $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
            $server.Databases.Refresh()
            # The pinned foreach ($cert in $db.Certificates) on the same database supplies the record the command must report.
            $pinnedFault = $null
            try {
                foreach ($offlineCertificate in $server.Databases[$offlineName].Certificates) { }
            } catch {
                $pinnedFault = $PSItem
            }
        }

        AfterAll {
            $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET ONLINE;")
            $server.Databases.Refresh()
            $server.KillDatabase($offlineName)
        }

        # evidence/pin-encryption-20261101.txt, case offline-bare: three ExceptionInGetEnumerator errors, then the next database.
        # Under a caller's try the pin ends at the first (cases offline-try, offline-exception), which no public API shows a
        # command; for this read-only failure the port writes it and goes on in both contexts (the caller-try line in the command).
        It "writes one failure per collection and goes on to the next database" {
            $pinnedFault | Should -Not -BeNullOrEmpty
            $merged = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $dbNameB -ErrorAction Continue 2>&1)
            $merged.Count | Should -Be 4
            foreach ($position in 0..2) {
                $merged[$position] | Should -BeOfType System.Management.Automation.ErrorRecord
                $merged[$position].FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                $merged[$position].Exception.GetType().FullName | Should -BeExactly $pinnedFault.Exception.GetType().FullName
                $merged[$position].Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
                $merged[$position].CategoryInfo.Category | Should -Be $pinnedFault.CategoryInfo.Category
            }
            $merged[3].Name | Should -BeExactly $certificateNameB
        }

        It "terminates at the first failure under -EnableException and -ErrorAction Stop" {
            foreach ($splatTermination in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $streamed = New-Object "System.Collections.Generic.List[object]"
                $caught = $null
                try {
                    Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $dbNameB @splatTermination | ForEach-Object { $streamed.Add($PSItem) }
                } catch {
                    $caught = $PSItem
                }
                $streamed.Count | Should -Be 0
                $caught.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                $caught.Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
            }
        }

        It "leaves it out unless -Database names it" {
            $offlineErrors = @()
            $null = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -ErrorVariable offlineErrors -ErrorAction SilentlyContinue)
            @($offlineErrors | Where-Object { "$($PSItem.Exception.GetBaseException().Message)" -like "*$offlineName*" }).Count | Should -Be 0
        }
    }

    Context "A database under TDE" {
        BeforeAll {
            $tdeName = "${prefix}_tde"
            $tdeCertificateName = "${prefix}_tde_cert"
            $tdeSymmetricName = "${prefix}_tde_sym"
            # This session reads master's certificates before the TDE certificate exists, so its cached collection never shows it.
            $staleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $null = @($staleServer.Databases["master"].Certificates).Count

            # The two lanes of a SQL version share this instance, so neither drops master's key; 15578 means the other lane made it.
            $masterDatabase = $server.Databases["master"]
            $masterDatabase.ExecuteNonQuery("BEGIN TRY IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$password'; END TRY BEGIN CATCH IF ERROR_NUMBER() <> 15578 THROW; END CATCH;")
            $masterDatabase.ExecuteNonQuery("CREATE CERTIFICATE [$tdeCertificateName] WITH SUBJECT = N'native';")
            $tdeDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $tdeName
            $tdeDatabase.Create()
            $tdeDatabase.ExecuteNonQuery("CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE [$tdeCertificateName];")
            $tdeDatabase.ExecuteNonQuery("CREATE SYMMETRIC KEY [$tdeSymmetricName] WITH ALGORITHM = AES_128 ENCRYPTION BY PASSWORD = N'$password';")
            $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$tdeName] SET ENCRYPTION ON;")
            # The drop in AfterAll waits on the encryption scan otherwise.
            $scanDeadline = (Get-Date).AddSeconds(60)
            do {
                Start-Sleep -Seconds 1
                $tdeState = $server.ConnectionContext.ExecuteScalar("SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID(N'$tdeName');")
            } while ($tdeState -ne 3 -and (Get-Date) -lt $scanDeadline)
            $staleServer.Databases.Refresh()
        }

        AfterAll {
            $server.Databases.Refresh()
            if ($server.Databases[$tdeName]) {
                $server.KillDatabase($tdeName)
            }
            $server.Databases["master"].ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$tdeCertificateName') DROP CERTIFICATE [$tdeCertificateName];")
            if ($staleServer) {
                $staleServer.ConnectionContext.Disconnect()
            }
        }

        It "reads the server certificate into the TDE row, ahead of the database's own objects" {
            $rows = @(Get-DbaDbEncryption @splatRead -Database $tdeName)
            $rows.Encryption | Should -Be @("EncryptionEnabled (TDE)", "Symmetric key")
            $tdeRow = $rows[0]
            @($tdeRow.PSObject.Properties.Name) | Should -Be $columns
            $tdeRow.Database | Should -BeExactly $tdeName
            $tdeRow.Name | Should -BeExactly $tdeCertificateName
            $tdeRow.Object | Should -BeOfType Microsoft.SqlServer.Management.Smo.Certificate
            $tdeRow.Object.Parent.Name | Should -BeExactly "master"
            $tdeRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "MasterKey"
            $tdeRow.EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
            $tdeRow.KeyLength | Should -BeNullOrEmpty
            $tdeRow.Owner | Should -BeExactly $tdeRow.Object.Owner
            $tdeRow.LastBackup | Should -Be $tdeRow.Object.LastBackupDate
            $tdeRow.ExpirationDate | Should -Be $tdeRow.Object.ExpirationDate
        }

        It "warns and leaves the database's objects unread when master does not show the certificate" {
            $staleWarnings = @()
            $results = @(Get-DbaDbEncryption -SqlInstance $staleServer -Database $tdeName, $dbNameB -WarningVariable staleWarnings -WarningAction SilentlyContinue)
            ($staleWarnings -join " ") | Should -BeLike "*Could not locate TDE server certificate*"
            $results.Name | Should -BeExactly $certificateNameB
        }

        It "throws for that certificate under -EnableException" {
            $caught = $null
            try {
                $null = Get-DbaDbEncryption -SqlInstance $staleServer -Database $tdeName -EnableException
            } catch {
                $caught = $PSItem
            }
            $caught.Exception.Message | Should -BeLike "Could not locate TDE server certificate*"
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbEncryption*"
        }

        # TDE on any database encrypts tempdb too, under a key no master certificate backs.
        It "returns tempdb's TDE row with no certificate to name" {
            $rows = @(Get-DbaDbEncryption @splatRead -Database tempdb)
            $rows[0].Encryption | Should -BeExactly "EncryptionEnabled (TDE)"
            $rows[0].Database | Should -BeExactly "tempdb"
            $rows[0].Name | Should -BeNullOrEmpty
            $rows[0].Object | Should -BeNullOrEmpty
        }

        It "reports the algorithm that encrypts tempdb" {
            $tempdbKey = $server.ConnectionContext.ExecuteWithResults("SELECT key_algorithm, key_length FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID(N'tempdb');").Tables[0].Rows[0]
            $rows = @(Get-DbaDbEncryption @splatRead -Database tempdb)
            $rows[0].EncryptionAlgorithm.ToString() | Should -Be "$($tempdbKey.key_algorithm)$($tempdbKey.key_length)"
        }
    }

    Context "Choosing databases" {
        It "compares -Database names ignoring case" {
            $results = @(Get-DbaDbEncryption @splatRead -Database $dbNameB.ToUpperInvariant())
            $results.Name | Should -BeExactly $certificateNameB
        }

        It "takes several names in -Database" {
            $results = @(Get-DbaDbEncryption @splatRead -Database $dbNameA, $dbNameB)
            $results.Database | Sort-Object -Unique | Should -Be @($dbNameA, $dbNameB)
            $results.Count | Should -Be 4
        }

        It "treats -Database values as exact names, not patterns" {
            $results = @(Get-DbaDbEncryption @splatRead -Database "${prefix}_?")
            $results.Count | Should -Be 0
        }

        It "leaves out -ExcludeDatabase names, ignoring case" {
            $results = @(Get-DbaDbEncryption @splatRead -Database $dbNameA, $dbNameB -ExcludeDatabase $dbNameA.ToUpperInvariant())
            $results.Name | Should -BeExactly $certificateNameB
        }

        It "applies -ExcludeDatabase to the default user databases" {
            $results = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbNameA -ErrorAction SilentlyContinue)
            $results.Database | Should -Contain $dbNameB
            $results.Database | Should -Not -Contain $dbNameA
        }

        It "reads user databases only by default" {
            $results = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -ErrorAction SilentlyContinue)
            $results.Database | Should -Contain $dbNameB
            $results.Database | Should -Not -Contain "master"
        }

        It "adds the system databases under -IncludeSystemDBs" {
            $results = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -IncludeSystemDBs -ErrorAction SilentlyContinue)
            $results.Database | Should -Contain "master"
            $results.Database | Should -Contain $dbNameB
        }

        It "reads a named system database without -IncludeSystemDBs" {
            $results = @(Get-DbaDbEncryption @splatRead -Database master)
            $results.Database | Sort-Object -Unique | Should -BeExactly "master"
        }

        It "treats an empty -Database as no filter, as if (`$Database) does" {
            $results = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database "" -ErrorAction SilentlyContinue)
            $results.Database | Should -Contain $dbNameB
        }
    }

    Context "Instances from the pipeline" {
        It "reads every piped instance" -Tag NativeChecklist:pipeline-multiple {
            $results = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Get-DbaDbEncryption -Database $dbNameB -EnableException)
            $results.Name | Should -Be @($certificateNameB, $certificateNameB)
        }

        It "reads every instance of a -SqlInstance array" {
            $results = @(Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -Database $dbNameB -EnableException)
            $results.Name | Should -Be @($certificateNameB, $certificateNameB)
        }
    }

    Context "Connection failures" {
        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaDbEncryption -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameB -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            ($connectWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Name | Should -BeExactly $certificateNameB
        }

        It "throws for that instance under -EnableException" -Tag NativeChecklist:enable-exception {
            { Get-DbaDbEncryption -SqlInstance $badInstance -EnableException } | Should -Throw
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaDbEncryption -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameB -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Name | Should -BeExactly $certificateNameB
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            $loginCertificateName = "${prefix}_login_cert"
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE CERTIFICATE [$loginCertificateName] ENCRYPTION BY PASSWORD = N'$password' WITH SUBJECT = N'native';")
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
            $results = @(Get-DbaDbEncryption -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Name | Should -BeExactly $loginCertificateName
            $results.Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaDbEncryption -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbEncryption.ps1 connects with its own try and Stop-Function, so
        # -EnableException reaches it and the command throws. Measured on the pin against this instance, both editions:
        # probes/pin-encryption-login-20261101.ps1, cases without-credential and without-credential-exception.
        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaDbEncryption -SqlInstance $loginInstance -Database $loginDbName -EnableException } | Should -Throw
        }
    }
}

# NativeChecklist azure-sqldb: tested. Measured on the pin: the certificates and keys read as on SQL Server, a certificate's
# LastBackup is null because Azure SQL Database has no BACKUP CERTIFICATE, and SMO gives no DatabaseEncryptionKey object, so
# the TDE row's EncryptionAlgorithm was a silent null that sys.dm_database_encryption_keys can answer.
Describe "Get-DbaDbEncryption native on Azure SQL Database" -Tag IntegrationTests {
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
                        if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
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

        # Six legs share the database: unique names and cleanup.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azurePassword = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
        $azureCertificateName = "native_encryption_cert_$azureSuffix"
        $azureAsymmetricName = "native_encryption_asym_$azureSuffix"
        $azureSymmetricName = "native_encryption_sym_$azureSuffix"
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE CERTIFICATE [$azureCertificateName] ENCRYPTION BY PASSWORD = N'$azurePassword' WITH SUBJECT = N'native';")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$azureAsymmetricName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$azurePassword';")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE SYMMETRIC KEY [$azureSymmetricName] WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = N'$azurePassword';")

        $azureRows = @(Get-DbaDbEncryption -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $azureSymmetricRow = $azureRows | Where-Object Name -eq $azureSymmetricName
    }

    AfterAll {
        if ($azureServer) {
            foreach ($statement in @(
                    "IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$azureCertificateName') DROP CERTIFICATE [$azureCertificateName];",
                    "IF EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = N'$azureAsymmetricName') DROP ASYMMETRIC KEY [$azureAsymmetricName];",
                    "IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'$azureSymmetricName') DROP SYMMETRIC KEY [$azureSymmetricName];"
                )) {
                $null = $azureServer.ConnectionContext.ExecuteNonQuery($statement)
            }
        }
        if ($azureLogicalServer) {
            $azureLogicalServer.ConnectionContext.Disconnect()
        }
    }

    It "reads the TDE row, certificates and keys" -Tag "NativeChecklist:azure-sqldb" {
        $azureEdition | Should -BeExactly "SqlDatabase"
        $azureRows[0].Encryption | Should -BeExactly "EncryptionEnabled (TDE)"
        $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $azureRows[0].Name | Should -BeNullOrEmpty
        $azureRows[0].Object | Should -BeNullOrEmpty

        $azureCertificateRow = $azureRows | Where-Object Name -eq $azureCertificateName
        $azureCertificateRow.Encryption | Should -BeExactly "Certificate"
        $azureCertificateRow.LastBackup | Should -BeNullOrEmpty
        $azureCertificateRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
        $azureCertificateRow.ExpirationDate | Should -Be $azureCertificateRow.Object.ExpirationDate
        $azureCertificateRow.Object | Should -BeOfType Microsoft.SqlServer.Management.Smo.Certificate

        $azureAsymmetricRow = $azureRows | Where-Object Name -eq $azureAsymmetricName
        $azureAsymmetricRow.Encryption | Should -BeExactly "Asymmetric key"
        $azureAsymmetricRow.EncryptionAlgorithm.ToString() | Should -BeExactly "Rsa2048"
        $azureAsymmetricRow.KeyLength | Should -Be 2048

        $azureSymmetricRow.Encryption | Should -BeExactly "Symmetric key"
        $azureSymmetricRow.KeyLength | Should -Be 256
    }

    It "reads the database through a connection to the logical server" {
        $results = @(Get-DbaDbEncryption -SqlInstance $azureLogicalServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $results[0].Encryption | Should -BeExactly "EncryptionEnabled (TDE)"
        $results.Name | Should -Contain $azureCertificateName
    }

    It "reports the algorithm that encrypts the database" {
        $azureRows[0].EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
        $results = @(Get-DbaDbEncryption -SqlInstance $azureLogicalServer -Database $TestConfig.AzureSqlDbName -EnableException)
        $results[0].EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
    }

    It "gives a symmetric key row the documented instance columns on Azure SQL Database" {
        $azureSymmetricRow.ComputerName | Should -BeExactly $azureServer.ComputerName
        $azureSymmetricRow.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
    }

    It "reports a symmetric key's own algorithm on Azure SQL Database" {
        $azureSymmetricRow.EncryptionAlgorithm.ToString() | Should -BeExactly "Aes256"
    }

    It "reports how a symmetric key is encrypted on Azure SQL Database" {
        $azureSymmetricRow.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
    }
}
