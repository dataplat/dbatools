#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbAsymmetricKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads $db.AsymmetricKeys.

Describe "Get-DbaDbAsymmetricKey native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run (lane-safe); AfterAll drops the databases and their keys.
        $prefix = "native_akey_" + [Guid]::NewGuid().ToString("N")
        $keyPassword = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dbNameA = "${prefix}_a"
        $dbNameB = "${prefix}_b"
        $keyNameA = "${prefix}_key_a"
        $keyNameB = "${prefix}_key_b"
        $keyNameC = "${prefix}_key_c"
        $databaseA = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbNameA
        $databaseA.Create()
        $databaseB = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbNameB
        $databaseB.Create()
        foreach ($keyName in @($keyNameA, $keyNameB)) {
            $databaseA.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$keyName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$keyPassword';")
        }
        $databaseB.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$keyNameC] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$keyPassword';")
        $badInstance = "TCP:127.0.0.1,1"
        $displaySet = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Owner", "KeyEncryptionAlgorithm", "KeyLength", "PrivateKeyEncryptionType", "Thumbprint")
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

    Context "Keys and filters" {
        It "returns the named key as a decorated SMO key with the pinned default view" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -Name $keyNameA -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.AsymmetricKey
            $result.ComputerName | Should -BeExactly $server.ComputerName
            $result.InstanceName | Should -BeExactly $server.ServiceName
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.Database | Should -BeExactly $dbNameA
            $result.DatabaseId | Should -Be $databaseA.ID
            $result.Name | Should -BeExactly $keyNameA
            $result.Owner | Should -BeExactly "dbo"
            $result.KeyEncryptionAlgorithm.ToString() | Should -BeExactly "Rsa2048"
            $result.KeyLength | Should -Be 2048
            $result.PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
            $result.Thumbprint | Should -Not -BeNullOrEmpty
            @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $displaySet
        }

        It "returns every key of every selected database" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameB, $keyNameC)
            ($results | Where-Object Name -eq $keyNameC).Database | Should -BeExactly $dbNameB
        }

        It "compares key names case-insensitively and takes several names" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -Name $keyNameA.ToUpperInvariant(), $keyNameC -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameC)
        }

        It "treats an empty -Name as no filter, as if (`$Name) does" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -Name "" -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameB)
        }

        It "excludes a database by name" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -ExcludeDatabase $dbNameA -EnableException)
            $results.Name | Should -BeExactly $keyNameC
        }

        It "returns nothing and warns nothing for a key name no database holds" {
            $missingWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -Name "${prefix}_missing" -WarningVariable missingWarnings)
            $results.Count | Should -Be 0
            $missingWarnings.Count | Should -Be 0
        }

        It "matches -Database wildcards, as the help documents" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database "${prefix}_?" -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameB, $keyNameC)
        }

        It "matches -ExcludeDatabase wildcards, as the help documents" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -ExcludeDatabase "*_a" -EnableException)
            $results.Name | Should -BeExactly $keyNameC
        }

        It "matches -Name wildcards, as the help documents" {
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -Name "${prefix}_key_?" -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameB, $keyNameC)
        }

        It "keeps a real key name with a wildcard character literal" {
            $starredName = "${prefix}_star*"
            $otherName = "${prefix}_starred"
            try {
                foreach ($keyName in @($starredName, $otherName)) {
                    $databaseB.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$keyName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$keyPassword';")
                }
                $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameB -Name $starredName -EnableException)
                $results.Name | Should -BeExactly $starredName
            } finally {
                foreach ($keyName in @($starredName, $otherName)) {
                    $databaseB.ExecuteNonQuery("IF ASYMKEY_ID(N'$keyName') IS NOT NULL DROP ASYMMETRIC KEY [$keyName];")
                }
            }
        }
    }

    Context "Piped databases" {
        It "reads every piped database" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB | Get-DbaDbAsymmetricKey -EnableException)
            ($results.Name | Sort-Object) | Should -Be @($keyNameA, $keyNameB, $keyNameC)
            foreach ($result in $results) {
                $result.ComputerName | Should -BeExactly $server.ComputerName
                $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            }
        }

        It "appends the -SqlInstance databases to each piped database" {
            $pipedDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA
            $results = @(@($pipedDatabase, $pipedDatabase) | Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $dbNameB -EnableException)
            $results.Database | Should -Be @($dbNameA, $dbNameA, $dbNameB, $dbNameA, $dbNameA, $dbNameB)
        }

        It "reports the instance of a database piped straight from SMO" {
            $rawServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            try {
                $rawDatabase = $rawServer.Databases[$dbNameB]
                $rawDatabase.PSObject.Properties["SqlInstance"] | Should -BeNullOrEmpty
                $results = @($rawDatabase | Get-DbaDbAsymmetricKey -EnableException)
                $results.Name | Should -BeExactly $keyNameC
                $results[0].ComputerName | Should -BeExactly $rawServer.ComputerName
                $results[0].InstanceName | Should -BeExactly $rawServer.ServiceName
                $results[0].SqlInstance | Should -BeExactly $rawServer.DomainInstanceName
            } finally {
                $rawServer.ConnectionContext.Disconnect()
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
                $results = @(Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $dbNameB -WarningVariable offlineWarnings -WarningAction SilentlyContinue)
                $results.Name | Should -BeExactly $keyNameC
                ($offlineWarnings -join " ") | Should -Match ([regex]::Escape("[$offlineName] is not accessible, skipping"))
            } finally {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET ONLINE;")
                $server.Databases.Refresh()
                $server.KillDatabase($offlineName)
            }
        }
    }

    Context "Connection failures" {
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbAsymmetricKey.ps1, the process block:
        #         if ($SqlInstance) {
        #             $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        #         }
        #
        # -EnableException never reaches the nested Get-DbaDatabase, whose Stop-Function warns "Failure" and moves on,
        # so the command warns and reads the next instance with or without the switch, and never throws here.
        # Baseline result 20261031T2342576050180Z ran these tests and the SQL login context on the compatibility hop at
        # 2f407dea3, which still ran the pinned process body: they passed on all six legs.
        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameB -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            ($connectWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Name | Should -BeExactly $keyNameC
        }

        It "warns the same under -EnableException, which the nested Get-DbaDatabase never gets" -Tag NativeChecklist:enable-exception {
            $enabledWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameB -EnableException -WarningVariable enabledWarnings -WarningAction SilentlyContinue)
            ($enabledWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Name | Should -BeExactly $keyNameC
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameB -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
            $results.Name | Should -BeExactly $keyNameC
        }
    }

    Context "A key read denied after a successful connection" {
        BeforeAll {
            $deniedUser = "${prefix}_denied"
            $databaseB.ExecuteNonQuery("CREATE USER [$deniedUser] WITHOUT LOGIN; DENY SELECT ON OBJECT::sys.asymmetric_keys TO [$deniedUser];")
            $splatDeniedConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $dbNameB
                NonPooledConnection = $true
                ClientName          = $deniedUser
                EnableException     = $true
            }
            $deniedServer = Connect-DbaInstance @splatDeniedConnection
            # Read while still sysadmin: the command's IsAccessible check stays on the cached value.
            $deniedDatabase = $deniedServer.Databases[$dbNameB]
            $deniedDatabase.IsAccessible | Should -BeTrue
            $null = $deniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$deniedUser';")
            $deniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedUser
            $goodDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA
            # The pinned foreach ($akey in $akeys) on the same object supplies the record the command must report.
            $pinnedFault = $null
            try {
                foreach ($deniedKey in $deniedDatabase.AsymmetricKeys) { }
            } catch {
                $pinnedFault = $PSItem
            }
        }

        AfterAll {
            if ($deniedServer) {
                $deniedServer.ConnectionContext.Disconnect()
            }
        }

        # The pinned fault is statement-terminating, so what follows depends on a caller's try, which no public API shows
        # a command. Inside one it ends the command: this test's only failure in baseline 20261031T2342576050180Z was that
        # record leaving the hop through Pester's own try. For this read-only failure the port writes it and goes on in
        # both contexts (the caller-try line in the command, as in Get-DbaAgentJobCategory).
        It "writes the failure and goes on to the next database" {
            $pinnedFault | Should -Not -BeNullOrEmpty
            $merged = @($goodDatabase, $deniedDatabase, $goodDatabase | Get-DbaDbAsymmetricKey -ErrorAction Continue 2>&1)
            $merged.Count | Should -Be 5
            $merged[2] | Should -BeOfType System.Management.Automation.ErrorRecord
            $merged[2].Exception.GetType().FullName | Should -BeExactly $pinnedFault.Exception.GetType().FullName
            $merged[2].Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
            $merged[2].CategoryInfo.Category | Should -Be $pinnedFault.CategoryInfo.Category
            $merged[2].FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            foreach ($position in @(0, 1, 3, 4)) {
                $merged[$position].Database | Should -BeExactly $dbNameA
            }
        }

        # The pinned $akeys | Where-Object leaves $akeys unfiltered when it fails, so its foreach reads the collection again and
        # writes a second copy of the failure, or the unfiltered keys when that read works. The port reads once: one failure,
        # no unfiltered rows (the caller-try line in the command, as in Get-DbaAgentJobCategory).
        It "writes one failure for a filtered read and goes on to the next database" {
            $merged = @($goodDatabase, $deniedDatabase, $goodDatabase | Get-DbaDbAsymmetricKey -Name $keyNameA -ErrorAction Continue 2>&1)
            $merged.Count | Should -Be 3
            $merged[0].Name | Should -BeExactly $keyNameA
            $merged[1] | Should -BeOfType System.Management.Automation.ErrorRecord
            $merged[1].Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
            $merged[2].Name | Should -BeExactly $keyNameA
        }

        It "terminates at the failure under -EnableException and -ErrorAction Stop" {
            foreach ($splatTermination in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $streamed = New-Object "System.Collections.Generic.List[object]"
                $caught = $null
                try {
                    $goodDatabase, $deniedDatabase, $goodDatabase | Get-DbaDbAsymmetricKey @splatTermination | ForEach-Object { $streamed.Add($PSItem) }
                } catch {
                    $caught = $PSItem
                }
                $streamed.Count | Should -Be 2
                $caught.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                $caught.Exception.Message | Should -BeExactly $pinnedFault.Exception.Message
            }
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            $loginKeyName = "${prefix}_login_key"
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$loginKeyName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$keyPassword';")
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
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Name | Should -BeExactly $loginKeyName
            $results.Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        # The nested Get-DbaDatabase gets no -EnableException (see "Connection failures"): a warning, no output, no throw.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $noLoginEnabledWarnings = @()
            $results = @(Get-DbaDbAsymmetricKey -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningVariable noLoginEnabledWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginEnabledWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}

Describe "Native Get-DbaDbAsymmetricKey on Azure SQL Database" -Tag IntegrationTests {
    # CREATE ASYMMETRIC KEY and sys.asymmetric_keys apply to Azure SQL Database (Microsoft Learn), and a password-protected
    # key needs no database master key.
    It "reads an asymmetric key in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        $azureKeyName = "native_akey_" + [Guid]::NewGuid().ToString("N")
        $azurePassword = "dbatools.IO-" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE ASYMMETRIC KEY [$azureKeyName] WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = N'$azurePassword';")
            $splatAzureKey = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                Name            = $azureKeyName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbAsymmetricKey @splatAzureKey)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.AsymmetricKey
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $azureRows[0].KeyLength | Should -Be 2048
            $azureRows[0].PrivateKeyEncryptionType.ToString() | Should -BeExactly "Password"
            $azureRows[0].Thumbprint | Should -Not -BeNullOrEmpty
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF ASYMKEY_ID(N'$azureKeyName') IS NOT NULL DROP ASYMMETRIC KEY [$azureKeyName];")
        }
    }
}
