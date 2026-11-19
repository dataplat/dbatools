#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaDbEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeAll {
    # A server certificate in master protects each test database's encryption key. Both are unique per run and
    # removed in AfterAll. The lab keeps a master key in master on every instance, as upstream CI does
    # (tests/appveyor.SQL*.ps1); one is created only where it is missing, and kept.
    function New-TdeFixture {
        param($Server, [string[]]$Names)
        $tdeSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $tdeCert = "dbatoolsci_tdecert_$tdeSuffix"
        $splatMaster = @{
            SqlInstance     = $Server
            Database        = "master"
            EnableException = $true
        }
        $hasMasterKey = Invoke-DbaQuery @splatMaster -Query "SELECT COUNT(*) AS n FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##'"
        if ($hasMasterKey.n -eq 0) {
            $null = Invoke-DbaQuery @splatMaster -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'dbatools.IO!Tde#2026'"
        }
        $null = Invoke-DbaQuery @splatMaster -Query "CREATE CERTIFICATE [$tdeCert] WITH SUBJECT = N'dbatoolsci TDE'"
        $created = @()
        foreach ($tdeName in $Names) {
            $null = Invoke-DbaQuery @splatMaster -Query "CREATE DATABASE [$tdeName]"
            $created += $tdeName
            $null = Invoke-DbaQuery -SqlInstance $Server -Database $tdeName -EnableException -Query "CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE [$tdeCert]"
            $null = Invoke-DbaQuery @splatMaster -Query "ALTER DATABASE [$tdeName] SET ENCRYPTION ON"
        }
        # Disabling is refused while the encryption scan runs, so wait until every database reports Encrypted (3).
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 1
            $pending = @(foreach ($tdeName in $Names) {
                    $state = Get-TdeState -Server $Server -Name $tdeName
                    if ($state -ne 3) { $tdeName }
                })
        } while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline)
        if ($pending.Count -gt 0) {
            throw "Fixture: encryption did not finish for $($pending -join ', ')"
        }
        [PSCustomObject]@{
            Certificate = $tdeCert
            Databases   = $created
        }
    }

    function Remove-TdeFixture {
        param($Server, $Fixture)
        if (-not $Fixture) { return }
        if ($Fixture.Databases) {
            $null = Remove-DbaDatabase -SqlInstance $Server -Database $Fixture.Databases -Confirm:$false
        }
        $null = Invoke-DbaQuery -SqlInstance $Server -Database master -Query "IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'$($Fixture.Certificate)') DROP CERTIFICATE [$($Fixture.Certificate)]"
    }

    # The encryption_state of a database's key, or $null when it has none.
    function Get-TdeState {
        param($Server, [string]$Name)
        $splatState = @{
            SqlInstance     = $Server
            Database        = "master"
            Query           = "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID(@name)"
            SqlParameter    = @{ name = $Name }
            EnableException = $true
        }
        $row = Invoke-DbaQuery @splatState
        if ($row) { $row.encryption_state } else { $null }
    }
}

Describe "Native Disable-DbaDbEncryption" -Tag IntegrationTests {
    BeforeAll {
        $tdeInstance = $TestConfig.InstanceSingle
        $tdeServer = Connect-DbaInstance -SqlInstance $tdeInstance -EnableException
        $tdeBadInstance = "TCP:127.0.0.1,1"
        $tdeRun = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $tdePipeA = "dbatoolsci_tdepipea_$tdeRun"
        $tdePipeB = "dbatoolsci_tdepipeb_$tdeRun"
        $tdeKeep = "dbatoolsci_tdekeep_$tdeRun"
        $tdeDrop = "dbatoolsci_tdedrop_$tdeRun"
        $tdeWhatIf = "dbatoolsci_tdewhatif_$tdeRun"
        $tdeMulti = "dbatoolsci_tdemulti_$tdeRun"
        $tdeMultiEE = "dbatoolsci_tdemultiee_$tdeRun"
        $tdeFixture = New-TdeFixture -Server $tdeServer -Names $tdePipeA, $tdePipeB, $tdeKeep, $tdeDrop, $tdeWhatIf, $tdeMulti, $tdeMultiEE
    }

    AfterAll {
        Remove-TdeFixture -Server $tdeServer -Fixture $tdeFixture
    }

    It "disables encryption on every piped database and drops their keys" -Tag "NativeChecklist:pipeline-multiple" {
        $tdeResult = @(Get-DbaDatabase -SqlInstance $tdeInstance -Database $tdePipeA, $tdePipeB | Disable-DbaDbEncryption -Confirm:$false)
        $tdeResult.Count | Should -Be 2
        $tdeExpected = (@($tdePipeA, $tdePipeB) | Sort-Object) -join ","
        (($tdeResult.DatabaseName | Sort-Object) -join ",") | Should -BeExactly $tdeExpected
        foreach ($tdeRow in $tdeResult) {
            $tdeRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $tdeRow.EncryptionEnabled | Should -BeFalse
            $tdeRow.ComputerName | Should -Not -BeNullOrEmpty
            $tdeRow.SqlInstance | Should -Be $tdeServer.DomainInstanceName
            ($tdeRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,DatabaseName,EncryptionEnabled"
            Get-TdeState -Server $tdeServer -Name $tdeRow.Name | Should -BeNullOrEmpty
        }
    }

    It "keeps the decrypted key with -NoEncryptionKeyDrop" {
        $tdeResult = @(Disable-DbaDbEncryption -SqlInstance $tdeInstance -Database $tdeKeep -NoEncryptionKeyDrop -Confirm:$false)
        $tdeResult.Count | Should -Be 1
        $tdeResult[0].DatabaseName | Should -BeExactly $tdeKeep
        $tdeResult[0].EncryptionEnabled | Should -BeFalse
        Get-TdeState -Server $tdeServer -Name $tdeKeep | Should -Be 1
    }

    It "drops the key with -NoEncryptionKeyDrop:`$false" -Tag "NativeChecklist:switch-false" {
        $splatTdeDrop = @{
            SqlInstance         = $tdeInstance
            Database            = $tdeDrop
            NoEncryptionKeyDrop = $false
            EnableException     = $false
            Confirm             = $false
        }
        $tdeResult = @(Disable-DbaDbEncryption @splatTdeDrop)
        $tdeResult.Count | Should -Be 1
        $tdeResult[0].EncryptionEnabled | Should -BeFalse
        Get-TdeState -Server $tdeServer -Name $tdeDrop | Should -BeNullOrEmpty
    }

    It "changes nothing under -WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $tdeResult = @(Disable-DbaDbEncryption -SqlInstance $tdeInstance -Database $tdeWhatIf -WhatIf)
        $tdeResult.Count | Should -Be 0
        Get-TdeState -Server $tdeServer -Name $tdeWhatIf | Should -Be 3
    }

    It "warns for an unreachable instance and still disables encryption on the next" -Tag "NativeChecklist:multi-instance-failure" {
        $splatTdeMulti = @{
            SqlInstance     = @($tdeBadInstance, $tdeInstance)
            Database        = $tdeMulti
            Confirm         = $false
            WarningVariable = "tdeWarning"
            WarningAction   = "SilentlyContinue"
        }
        $tdeResult = @(Disable-DbaDbEncryption @splatTdeMulti)
        $tdeResult.Count | Should -Be 1
        $tdeResult[0].DatabaseName | Should -BeExactly $tdeMulti
        ($tdeWarning -join " ") | Should -BeLike "*Failure*"
        Get-TdeState -Server $tdeServer -Name $tdeMulti | Should -BeNullOrEmpty
    }

    # The pinned function lists databases through Get-DbaDatabase without passing -EnableException, so a connection
    # failure there is a warning even under -EnableException (Get-DbaDatabase.ps1 connect catch, Stop-Function -Continue).
    It "only warns for an unreachable instance under -EnableException, as the nested Get-DbaDatabase does" -Tag "NativeChecklist:enable-exception" {
        $splatTdeMultiEE = @{
            SqlInstance     = @($tdeBadInstance, $tdeInstance)
            Database        = $tdeMultiEE
            Confirm         = $false
            EnableException = $true
            WarningVariable = "tdeWarning"
            WarningAction   = "SilentlyContinue"
        }
        $tdeResult = @(Disable-DbaDbEncryption @splatTdeMultiEE)
        $tdeResult.Count | Should -Be 1
        $tdeResult[0].EncryptionEnabled | Should -BeFalse
        ($tdeWarning -join " ") | Should -BeLike "*Failure*"
    }

    # The nested Get-DbaDatabase Stop-Function record reaches the caller's -ErrorVariable, as the pinned nested call puts it
    # there (central CaptureErrorVariable, the shared WarnNestedStopFunction). The pin's also holds the caught
    # Connect-DbaInstance records and blank entries: accepted difference omitted-consequential-records.
    It "keeps the connection failure of an unreachable instance in -ErrorVariable" {
        $splatTdeUnreachable = @{
            SqlInstance     = $tdeBadInstance
            Database        = $tdeMulti
            Confirm         = $false
            WarningVariable = "tdeWarning"
            WarningAction   = "SilentlyContinue"
            ErrorVariable   = "tdeErrors"
        }
        $tdeResult = @(Disable-DbaDbEncryption @splatTdeUnreachable)
        $tdeResult.Count | Should -Be 0
        ($tdeWarning -join " ") | Should -BeLike "*Failure*"
        $tdeErrors = @($tdeErrors)
        $tdeErrors.Count | Should -Be 1
        $tdeErrors[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $tdeErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        "$($tdeErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        $tdeErrors[0].Exception.Message | Should -Not -BeNullOrEmpty
        $tdeErrors[0].Exception.InnerException | Should -Not -BeNullOrEmpty
    }

    It "warns without -Database and returns nothing" {
        $tdeResult = @(Disable-DbaDbEncryption -SqlInstance $tdeInstance -Confirm:$false -WarningVariable tdeWarning -WarningAction SilentlyContinue)
        $tdeResult.Count | Should -Be 0
        ($tdeWarning -join " ") | Should -BeLike "*You must specify Database or ExcludeDatabase when using SqlInstance*"
    }

    It "throws without -Database under -EnableException" -Tag "NativeChecklist:enable-exception" {
        { Disable-DbaDbEncryption -SqlInstance $tdeInstance -Confirm:$false -EnableException } | Should -Throw "*You must specify Database or ExcludeDatabase when using SqlInstance*"
    }
}

Describe "Native Disable-DbaDbEncryption over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginDb = "dbatoolsci_tdelogin_$([guid]::NewGuid().ToString("N").Substring(0, 10))"
            $loginFixture = New-TdeFixture -Server $loginServer -Names $loginDb
        }

        AfterAll {
            Remove-TdeFixture -Server $loginServer -Fixture $loginFixture
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginResult = @(Disable-DbaDbEncryption -SqlInstance $loginInstance -Database $loginDb -Confirm:$false -WarningVariable loginWarning -WarningAction SilentlyContinue)
            $loginResult.Count | Should -Be 0
            ($loginWarning -join " ") | Should -BeLike "*Failure*"
            Get-TdeState -Server $loginServer -Name $loginDb | Should -Be 3
        }

        # Get-DbaDatabase is called without -EnableException (pinned Disable-DbaDbEncryption.ps1 process block), and its
        # connect catch runs Stop-Function -Continue, so the pinned function warns here and does not throw.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $loginResult = @(Disable-DbaDbEncryption -SqlInstance $loginInstance -Database $loginDb -Confirm:$false -EnableException -WarningVariable loginWarning -WarningAction SilentlyContinue)
            $loginResult.Count | Should -Be 0
            ($loginWarning -join " ") | Should -BeLike "*Failure*"
        }

        It "works with -SqlCredential" {
            $loginResult = @(Disable-DbaDbEncryption -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDb -Confirm:$false -EnableException)
            $loginResult.Count | Should -Be 1
            $loginResult[0].DatabaseName | Should -BeExactly $loginDb
            $loginResult[0].EncryptionEnabled | Should -BeFalse
            Get-TdeState -Server $loginServer -Name $loginDb | Should -BeNullOrEmpty
        }
    }
}

# Azure SQL Database supports ALTER DATABASE ... SET ENCRYPTION OFF (https://learn.microsoft.com/azure/azure-sql/database/transparent-data-encryption-tde-overview#manage-transparent-data-encryption)
# but not DROP DATABASE ENCRYPTION KEY, whose Applies-to list omits it (https://learn.microsoft.com/sql/t-sql/statements/drop-database-encryption-key-transact-sql).
# The six legs share one database, so each leg takes an exclusive session application lock on a dedicated connection
# for the whole command. Azure SQL Database refuses a new encryption scan while the last one's changes wait for a log
# backup ("... pending log backup. Please wait several minutes ...", red a98e6b9e), and it takes log backups only every 3
# to 25 minutes while the database is active (manager measurement 2026-11-15T23:23Z). So no leg turns encryption back
# on: a leg that finds the database encrypted decrypts it, and the legs after it run the command on the decrypted
# database. The Context's name records which state each leg found. After every run the lab turns encryption on again,
# and the next run starts only once that scan is in a log backup (watchman bb41de6c, the standing lab step); a leg
# still checks it, for at most 5 minutes. Every bound below keeps a leg well inside the runner's 3600 s, and a leg that
# cannot get the lock in time fails at sp_getapplock.
Describe "Native Disable-DbaDbEncryption on Azure SQL Database" -Tag IntegrationTests {
    Context "Azure SQL Database, found at encryption_state <azureFoundState>" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
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
            $azureDbName = $TestConfig.AzureSqlDbName
            # Every fixture query (DB_ID(), DB_NAME()) reads the connection's own database, which must be the fixture's.
            $azureContext = $azureServer.Query("SELECT DB_NAME() AS name").name
            if ($azureContext -ne $azureDbName) { throw "Fixture: the connection is in database $azureContext, not $azureDbName" }

            $azureLocked = $false
            $azureFoundState = "unknown"
            function Get-AzureTdeState {
                $row = $azureServer.Query("SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID()")
                if ($row) { $row.encryption_state } else { $null }
            }
            function Wait-AzureTdeState ([int[]]$Wanted) {
                $deadline = (Get-Date).AddMinutes(3)
                do {
                    $state = Get-AzureTdeState
                    if ($state -in $Wanted) { return $state }
                    Start-Sleep -Seconds 5
                } while ((Get-Date) -lt $deadline)
                throw "Fixture: encryption_state stayed $state, wanted $($Wanted -join ' or ')"
            }
            # An encrypted database can be decrypted only once a log backup of this database has started and finished after
            # its last encryption scan (sys.dm_database_backups, backup_type L, filtered to this database's own name). The
            # standing lab step makes that true before a run starts; this checks it, for at most 5 minutes.
            function Wait-AzureScanBackedUp {
                $deadline = (Get-Date).AddMinutes(5)
                do {
                    $scan = $azureServer.Query("SELECT k.encryption_state, k.encryption_scan_modify_date, CASE WHEN k.encryption_scan_modify_date IS NULL OR EXISTS (SELECT 1 FROM sys.dm_database_backups AS b WHERE b.backup_type = 'L' AND b.logical_database_name = DB_NAME() AND b.backup_start_date > k.encryption_scan_modify_date AND b.backup_finish_date > k.encryption_scan_modify_date) THEN 1 ELSE 0 END AS backed_up FROM sys.dm_database_encryption_keys AS k WHERE k.database_id = DB_ID()")
                    if (-not $scan -or $scan.encryption_state -ne 3 -or $scan.backed_up -eq 1) { return }
                    Start-Sleep -Seconds 15
                } while ((Get-Date) -lt $deadline)
                throw "Fixture: the encryption scan of $azureDbName at $($scan.encryption_scan_modify_date) (UTC) had no finished log backup within 5 minutes; the lab step before a run was not met"
            }

            # Runs Disable-DbaDbEncryption -Confirm:$false -Verbose on one database in a fresh runspace with this module,
            # and stops it when it has not returned within the bound.
            function Invoke-TdeBounded {
                param($InputObject, [int]$Seconds)
                $boundState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
                $boundState.ImportPSModule([string[]]@((Join-Path (Get-Module dbatools).ModuleBase "dbatools.psd1")))
                $boundRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($boundState)
                $boundRunspace.Open()
                $boundShell = [powershell]::Create()
                $boundShell.Runspace = $boundRunspace
                $splatBound = @{
                    InputObject = $InputObject
                    Confirm     = $false
                    Verbose     = $true
                }
                $null = $boundShell.AddCommand("Disable-DbaDbEncryption").AddParameters($splatBound)
                $boundHandle = $boundShell.BeginInvoke()
                $boundRun = [PSCustomObject]@{
                    Completed = $boundHandle.AsyncWaitHandle.WaitOne($Seconds * 1000)
                    Output    = @()
                    Verbose   = @()
                    Warnings  = @()
                    Error     = $null
                }
                try {
                    if ($boundRun.Completed) {
                        $boundRun.Output = @($boundShell.EndInvoke($boundHandle))
                    } else {
                        $boundShell.Stop()
                    }
                } catch {
                    $boundRun.Error = $PSItem.Exception.GetBaseException().Message
                }
                $boundRun.Verbose = @($boundShell.Streams.Verbose | ForEach-Object { $PSItem.Message })
                $boundRun.Warnings = @($boundShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                $boundShell.Dispose()
                $boundRunspace.Dispose()
                $boundRun
            }

            # The lock lives on its own physical (non-pooled) session, so closing it always releases the lock.
            $splatLockBuilder = @{
                SqlInstance         = $TestConfig.AzureSqlDbServer
                Database            = $azureDbName
                SqlCredential       = $TestConfig.AzureSqlDbCred
                NonPooledConnection = $true
            }
            $lockBuilder = New-DbaConnectionStringBuilder @splatLockBuilder
            $lockBuilder["Connect Timeout"] = 60
            $azureLock = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList $lockBuilder.ConnectionString
            $azureLock.Open()
            $lockCommand = $azureLock.CreateCommand()
            $lockCommand.CommandTimeout = 0
            $lockCommand.CommandText = "DECLARE @r int; EXEC @r = sp_getapplock @Resource = N'dbatoolsci_Disable-DbaDbEncryption', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 1200000; SELECT @r;"
            $lockResult = $lockCommand.ExecuteScalar()
            if ($lockResult -lt 0) { throw "Fixture: sp_getapplock returned $lockResult" }
            $azureLocked = $true

            # Decrypted, or encrypted with its last scan in a log backup: either way the command can run once.
            $azureFoundState = Wait-AzureTdeState -Wanted 1, 3
            if ($azureFoundState -eq 3) {
                Wait-AzureScanBackedUp
            }
        }

        AfterAll {
            # Only the leg holding the lock touches encryption, and it never hands the database over mid-change.
            try {
                if ($azureLocked) {
                    $null = Wait-AzureTdeState -Wanted 1, 3
                }
            } finally {
                if ($azureLock) {
                    if ($azureLocked) {
                        $releaseCommand = $azureLock.CreateCommand()
                        $releaseCommand.CommandText = "EXEC sp_releaseapplock @Resource = N'dbatoolsci_Disable-DbaDbEncryption', @LockOwner = 'Session';"
                        $null = $releaseCommand.ExecuteNonQuery()
                    }
                    $azureLock.Dispose()
                }
            }
        }

        It "decrypts the database and leaves its service-managed key, with no warning" {
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            # The released command never returned here (manager probe f9cb91b3), so it runs in its own runspace and is
            # stopped after five minutes; the verbose state lines and the engine's own state explain any failure.
            $azureRun = Invoke-TdeBounded -InputObject $azureServer.Databases[$azureDbName] -Seconds 300
            $azureDiagnosis = "completed=$($azureRun.Completed); engine state now=$(Get-AzureTdeState); last state lines: $(@($azureRun.Verbose | Where-Object { $_ -like '*Database state*' } | Select-Object -Last 3) -join ' / '); warnings: $($azureRun.Warnings -join ' / '); error: $($azureRun.Error)"
            $azureRun.Completed | Should -BeTrue -Because $azureDiagnosis
            $azureRun.Output.Count | Should -Be 1 -Because $azureDiagnosis
            $azureRun.Output[0].DatabaseName | Should -BeExactly $azureDbName
            $azureRun.Output[0].EncryptionEnabled | Should -BeFalse
            $azureRun.Warnings | Should -BeNullOrEmpty -Because $azureDiagnosis
        }
    }
}
