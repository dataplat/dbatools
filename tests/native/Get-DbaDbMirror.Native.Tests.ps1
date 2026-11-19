#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMirror",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads mirroring state.
# NativeChecklist: switch-false N/A -- The pinned command has no switch of its own; -EnableException is the common switch and is tested below.
# NativeSkip: Get-DbaDbMirror -- covered: Native Get-DbaDbMirror.A mirroring session.returns both databases, one by name and one from each partner

Describe "Native Get-DbaDbMirror" -Tag IntegrationTests {
    BeforeAll {
        # The pinned Integration Describe skips "because Mirroring need additional setup": this is that setup, on the same two instances
        # with a third for the witness. A leg claims its instances, so only the names need to be unique.
        $mirrorSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $mirrorDb1 = "dbatoolsci_mirror1_$mirrorSuffix"
        $mirrorDb2 = "dbatoolsci_mirror2_$mirrorSuffix"
        $mirrorOffline = "dbatoolsci_mirroroff_$mirrorSuffix"
        $mirrorPrincipal = $TestConfig.InstanceMulti1
        $mirrorPartner = $TestConfig.InstanceMulti2
        $mirrorWitness = $TestConfig.InstanceCopy1
        $mirrorOwn = $mirrorDb1, $mirrorDb2
        $mirrorBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $mirrorStateQuery = "SELECT DB_NAME(database_id) AS name, mirroring_state_desc, mirroring_partner_name, mirroring_partner_instance, mirroring_guid, mirroring_role_sequence, mirroring_safety_sequence, mirroring_connection_timeout FROM sys.database_mirroring WHERE mirroring_guid IS NOT NULL;"
        $mirrorWitnessQuery = "SELECT database_name, principal_server_name, safety_level_desc, partner_sync_state FROM master.sys.database_mirroring_witnesses;"
        $mirrorEndpointQuery = "SELECT name FROM sys.database_mirroring_endpoints;"
        $mirrorWindowsLoginQuery = "SELECT name FROM sys.server_principals WHERE type IN ('U', 'G');"

        $mirrorServers = @{
            Principal = Connect-DbaInstance -SqlInstance $mirrorPrincipal -EnableException
            Partner   = Connect-DbaInstance -SqlInstance $mirrorPartner -EnableException
            Witness   = Connect-DbaInstance -SqlInstance $mirrorWitness -EnableException
        }

        # Invoke-DbaDbMirroring adds a login for the service account where it is missing, and this setup adds endpoints. What was added goes in AfterAll.
        $mirrorBefore = @{ }
        foreach ($mirrorRole in $mirrorServers.Keys) {
            $mirrorBefore[$mirrorRole] = @{
                Endpoints = @($mirrorServers[$mirrorRole].Query($mirrorEndpointQuery) | ForEach-Object { $PSItem.name })
                Logins    = @($mirrorServers[$mirrorRole].Query($mirrorWindowsLoginQuery) | ForEach-Object { $PSItem.name })
            }
        }

        function Remove-NativeMirrorSession {
            param($Server, [string]$Name)
            $null = $Server.Query("IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE database_id = DB_ID(N'$Name') AND mirroring_guid IS NOT NULL) ALTER DATABASE [$Name] SET PARTNER OFF;")
        }

        function Remove-NativeMirrorAdditions {
            param($Server, $Before)
            # Each drop on its own, so that one failure leaves the next to run.
            foreach ($mirrorEndpoint in @($Server.Query($mirrorEndpointQuery) | ForEach-Object { $PSItem.name })) {
                if ($mirrorEndpoint -notin $Before.Endpoints) {
                    try {
                        $null = $Server.Query("DROP ENDPOINT [$mirrorEndpoint];")
                    } catch {
                        Write-Warning "Cleanup of endpoint ${mirrorEndpoint}: $PSItem"
                    }
                }
            }
            foreach ($mirrorLogin in @($Server.Query($mirrorWindowsLoginQuery) | ForEach-Object { $PSItem.name })) {
                if ($mirrorLogin -notin $Before.Logins) {
                    try {
                        # SQL Agent logs in as the service account once its login exists, which blocks the drop.
                        $null = $Server.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$mirrorLogin'; EXEC sys.sp_executesql @kill;")
                        $null = $Server.Query("DROP LOGIN [$mirrorLogin];")
                    } catch {
                        Write-Warning "Cleanup of login ${mirrorLogin}: $PSItem"
                    }
                }
            }
        }
    }

    Context "A mirroring session" {
        BeforeAll {
            $null = $mirrorServers.Principal.Query("CREATE DATABASE [$mirrorDb1];")
            $null = $mirrorServers.Principal.Query("CREATE DATABASE [$mirrorDb2];")
            $null = $mirrorServers.Principal.Query("CREATE DATABASE [$mirrorOffline];")
            $null = $mirrorServers.Principal.Query("ALTER DATABASE [$mirrorOffline] SET OFFLINE WITH ROLLBACK IMMEDIATE;")

            # With the endpoints New-DbaEndpoint makes, the witness dials TCP://0.0.0.0:5022 (error 10049) and SET WITNESS fails with error 1456.
            foreach ($mirrorRole in $mirrorServers.Keys) {
                if (-not $mirrorBefore[$mirrorRole].Endpoints) {
                    $null = $mirrorServers[$mirrorRole].Query("CREATE ENDPOINT [dbatoolsci_mirror_$mirrorSuffix] STATE = STARTED AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL) FOR DATABASE_MIRRORING (ROLE = ALL, AUTHENTICATION = WINDOWS NEGOTIATE, ENCRYPTION = REQUIRED ALGORITHM AES);")
                }
            }

            # One database per call: the pinned function takes fresh backups for the first database of a call only, and the port keeps that
            # (its UseLastBackup state), so a second database in the same call fails with error 1475.
            $splatMirroring = @{
                Primary         = $mirrorPrincipal
                Mirror          = $mirrorPartner
                Force           = $true
                SharedPath      = $TestConfig.Temp
                EnableException = $true
            }
            (Invoke-DbaDbMirroring @splatMirroring -Database $mirrorDb1).Status | Should -Be "Success"

            # The -Witness call grants each service account CONNECT on the witness endpoint, so the witness gets their logins first.
            # AfterAll drops the logins this run added.
            foreach ($mirrorAccount in @($mirrorServers.Principal.ServiceAccount, $mirrorServers.Partner.ServiceAccount, $mirrorServers.Witness.ServiceAccount | Where-Object { $PSItem } | Select-Object -Unique)) {
                $null = $mirrorServers.Witness.Query("IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE sid = SUSER_SID(N'$mirrorAccount')) CREATE LOGIN [$mirrorAccount] FROM WINDOWS;")
            }
            (Invoke-DbaDbMirroring @splatMirroring -Database $mirrorDb2 -Witness $mirrorWitness).Status | Should -Be "Success"

            for ($mirrorAttempt = 0; $mirrorAttempt -lt 30; $mirrorAttempt++) {
                $mirrorStates = @($mirrorServers.Principal.Query($mirrorStateQuery) | Where-Object name -in $mirrorOwn)
                $mirrorWitnessRows = @($mirrorServers.Witness.Query($mirrorWitnessQuery) | Where-Object { $PSItem.database_name -eq $mirrorDb2 -and $PSItem.partner_sync_state -eq 5 })
                if (@($mirrorStates | Where-Object mirroring_state_desc -eq "SYNCHRONIZED").Count -eq 2 -and $mirrorWitnessRows.Count -eq 1) { break }
                Start-Sleep -Seconds 2
            }
        }

        AfterAll {
            # Each step on its own, and each statement guarded, so that after a BeforeAll that stopped half way, or a failed step, the rest
            # still runs.
            foreach ($mirrorStep in @(
                    { $null = $mirrorServers.Principal.Query("IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE database_id = DB_ID(N'$mirrorDb2') AND mirroring_witness_name <> N'') ALTER DATABASE [$mirrorDb2] SET WITNESS OFF;") },
                    { Remove-NativeMirrorSession -Server $mirrorServers.Principal -Name $mirrorDb1 },
                    { Remove-NativeMirrorSession -Server $mirrorServers.Principal -Name $mirrorDb2 },
                    { Start-Sleep -Seconds 3 },
                    { Remove-NativeMirrorSession -Server $mirrorServers.Partner -Name $mirrorDb1 },
                    { Remove-NativeMirrorSession -Server $mirrorServers.Partner -Name $mirrorDb2 },
                    { $null = $mirrorServers.Principal.Query("IF DB_ID(N'$mirrorOffline') IS NOT NULL ALTER DATABASE [$mirrorOffline] SET ONLINE;") }
                )) {
                try {
                    & $mirrorStep
                } catch {
                    Write-Warning "Cleanup: $PSItem"
                }
            }
            foreach ($mirrorServer in $mirrorServers.Values) {
                foreach ($mirrorName in $mirrorDb1, $mirrorDb2, $mirrorOffline) {
                    try {
                        $null = $mirrorServer.Query("IF DB_ID(N'$mirrorName') IS NOT NULL DROP DATABASE [$mirrorName];")
                    } catch {
                        Write-Warning "Cleanup of ${mirrorName}: $PSItem"
                    }
                }
            }
            # Only where the snapshot was taken: without one, every endpoint and login would look added.
            foreach ($mirrorRole in @($mirrorBefore.Keys)) {
                try {
                    Remove-NativeMirrorAdditions -Server $mirrorServers[$mirrorRole] -Before $mirrorBefore[$mirrorRole]
                } catch {
                    Write-Warning "Cleanup on ${mirrorRole}: $PSItem"
                }
            }
            Get-ChildItem -Path $TestConfig.Temp -Filter "dbatoolsci_mirror*$mirrorSuffix*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        # The three pinned tests, asserted against real mirroring.
        It "returns both databases, one by name and one from each partner" {
            @(Get-DbaDbMirror -SqlInstance $mirrorPartner | Where-Object Name -in $mirrorOwn).Count | Should -Be 2
            @(Get-DbaDbMirror -SqlInstance $mirrorPartner -Database $mirrorDb2).Count | Should -Be 1
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal, $mirrorPartner -Database $mirrorDb2).Count | Should -Be 2
        }

        It "reports each partner's session as sys.database_mirroring does" {
            foreach ($mirrorRole in "Principal", "Partner") {
                $mirrorState = @($mirrorServers[$mirrorRole].Query($mirrorStateQuery) | Where-Object name -eq $mirrorDb1)[0]
                $mirrorRow = Get-DbaDbMirror -SqlInstance $mirrorServers[$mirrorRole] -Database $mirrorDb1
                $mirrorRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
                $mirrorRow.Name | Should -BeExactly $mirrorDb1
                $mirrorRow.SqlInstance | Should -BeExactly $mirrorServers[$mirrorRole].DomainInstanceName
                $mirrorRow.MirroringPartner | Should -BeExactly $mirrorState.mirroring_partner_name
                $mirrorRow.MirroringPartnerInstance | Should -BeExactly $mirrorState.mirroring_partner_instance
                $mirrorRow.MirroringID | Should -Be $mirrorState.mirroring_guid
                $mirrorRow.MirroringRoleSequence | Should -Be $mirrorState.mirroring_role_sequence
                $mirrorRow.MirroringSafetySequence | Should -Be $mirrorState.mirroring_safety_sequence
                $mirrorRow.MirroringTimeout | Should -Be $mirrorState.mirroring_connection_timeout
                $mirrorRow.MirroringStatus | Should -Be "Synchronized"
                $mirrorRow.MirroringSafetyLevel | Should -Be "Full"
                $mirrorRow.MirroringFailoverLogSequenceNumber | Should -BeOfType [decimal]
                $mirrorRow.MirroringRedoQueueMaxSize | Should -Be 0
                $mirrorRow.MirroringWitness | Should -BeNullOrEmpty
                $mirrorRow.MirroringWitnessStatus | Should -Be "Unknown"
            }
        }

        It "keeps the pinned default view and the members Get-DbaDatabase adds" {
            $mirrorRow = Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database $mirrorDb1
            ($mirrorRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,MirroringSafetyLevel,MirroringStatus,MirroringPartner,MirroringPartnerInstance,MirroringFailoverLogSequenceNumber,MirroringID,MirroringRedoQueueMaxSize,MirroringRoleSequence,MirroringSafetySequence,MirroringTimeout,MirroringWitness,MirroringWitnessStatus"
            (@($mirrorRow.PSObject.Members | Where-Object { "$($PSItem.MemberType)" -eq "NoteProperty" } | ForEach-Object { $PSItem.Name }) -join ",") | Should -BeExactly "BackupStatus,ComputerName,InstanceName,SqlInstance,LastRead,LastWrite,IsCdcEnabled,Size"
            (@($mirrorRow.PSObject.Members | Where-Object { "$($PSItem.MemberType)" -eq "AliasProperty" } | ForEach-Object { "$($PSItem.Name)=$($PSItem.ReferencedMemberName)" }) -join ",") | Should -BeExactly "SizeMB=Size,Compatibility=CompatibilityLevel,Encrypted=EncryptionEnabled,LastFullBackup=LastBackupDate,LastDiffBackup=LastDifferentialBackupDate,LastLogBackup=LastLogBackupDate"
            $mirrorRow.IsCdcEnabled | Should -BeOfType [bool]
            $mirrorRow.Size | Should -BeOfType [double]
            $mirrorRow.SizeMB | Should -Be $mirrorRow.Size
            $mirrorRow.Compatibility | Should -Be $mirrorRow.CompatibilityLevel
            $mirrorRow.BackupStatus | Should -BeNullOrEmpty
            $mirrorRow.LastRead | Should -BeNullOrEmpty
            $mirrorRow.LastWrite | Should -BeNullOrEmpty
        }

        It "reports the size of a mirror copy from sys.master_files, which SMO cannot read" {
            $mirrorRow = Get-DbaDbMirror -SqlInstance $mirrorPartner -Database $mirrorDb2
            $mirrorRow.Status.ToString() | Should -BeExactly "Restoring"
            $mirrorRow.Size | Should -BeOfType [decimal]
            $mirrorRow.Size | Should -BeGreaterThan 0
        }

        It "writes the databases in the order sys.databases gives" {
            $mirrorNames = @($mirrorServers.Partner.Query("SELECT name FROM sys.databases;") | Where-Object name -in $mirrorOwn | ForEach-Object { $PSItem.name })
            @(Get-DbaDbMirror -SqlInstance $mirrorPartner | Where-Object Name -in $mirrorOwn).Name | Should -Be $mirrorNames
        }

        It "matches -Database in any case" {
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database $mirrorDb2.ToUpperInvariant()).Name | Should -BeExactly $mirrorDb2
        }

        It "honours a wildcard in -Database" {
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database "dbatoolsci_mirror?_$mirrorSuffix").Count | Should -Be 2
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database "dbatoolsci_mirror2_*$mirrorSuffix").Name | Should -BeExactly $mirrorDb2
        }

        It "reads every database for an empty -Database" {
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database @() | Where-Object Name -in $mirrorOwn).Count | Should -Be 2
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database $null | Where-Object Name -in $mirrorOwn).Count | Should -Be 2
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database "" | Where-Object Name -in $mirrorOwn).Count | Should -Be 2
        }

        It "writes nothing for a database that is not mirrored" {
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database master).Count | Should -Be 0
        }

        It "passes over an offline database beside a mirrored one, with no record" {
            $mirrorErrors = $null
            $mirrorRows = @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal -Database $mirrorOffline, $mirrorDb2 -ErrorVariable mirrorErrors)
            $mirrorRows.Name | Should -BeExactly $mirrorDb2
            $mirrorErrors.Count | Should -Be 0
        }

        # The streams, not -ErrorVariable: the pinned function's catch leaves its index failure there, one per instance, but writes no record.
        It "goes on to the next instance after one with no such database" {
            $mirrorStream = @(Get-DbaDbMirror -SqlInstance $mirrorWitness, $mirrorPrincipal -Database $mirrorDb1 2>&1 3>&1)
            $mirrorStream.Count | Should -Be 1
            $mirrorStream[0].Name | Should -BeExactly $mirrorDb1
            @(Get-DbaDbMirror -SqlInstance $mirrorPrincipal, $mirrorPartner -Database "dbatoolsci_mirror_missing_$mirrorSuffix" 2>&1 3>&1).Count | Should -Be 0
        }

        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $mirrorRows = @($mirrorPrincipal, $mirrorPartner | Get-DbaDbMirror -Database $mirrorDb2)
            $mirrorRows.Count | Should -Be 2
            $mirrorRows.SqlInstance | Should -Be @($mirrorServers.Principal.DomainInstanceName, $mirrorServers.Partner.DomainInstanceName)
        }

        It "takes a connected server" {
            @(Get-DbaDbMirror -SqlInstance $mirrorServers.Principal -Database $mirrorDb2).Name | Should -BeExactly $mirrorDb2
        }

        # The warning stream, not -WarningVariable: on the pinned function that variable holds more entries than the stream for a nested warning.
        It "warns under Get-DbaDatabase's name for an instance it cannot reach, then reads the next" -Tag "NativeChecklist:multi-instance-failure" {
            $mirrorUnreachableErrors = @()
            $mirrorStream = @(Get-DbaDbMirror -SqlInstance $mirrorBadInstance, $mirrorPrincipal -Database $mirrorDb2 -EnableException:$false -ErrorVariable mirrorUnreachableErrors 3>&1)
            $mirrorStream.Count | Should -Be 2
            $mirrorStream[0] | Should -BeOfType System.Management.Automation.WarningRecord
            "$($mirrorStream[0])" | Should -BeLike "*Get-DbaDatabase*Failure | *"
            $mirrorStream[1].Name | Should -BeExactly $mirrorDb2

            # The caller's -ErrorVariable holds the nested Get-DbaDatabase Stop-Function record, as the pinned nested call puts it there
            # (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the caught Connect-DbaInstance records, its own
            # catch's index failure and blank entries: accepted difference omitted-consequential-records.
            $mirrorUnreachableErrors = @($mirrorUnreachableErrors)
            $mirrorUnreachableErrors.Count | Should -Be 1
            $mirrorUnreachableErrors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $mirrorUnreachableErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
            "$($mirrorUnreachableErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $mirrorUnreachableErrors[0].Exception.Message | Should -Not -BeNullOrEmpty
            $mirrorUnreachableErrors[0].Exception.InnerException | Should -Not -BeNullOrEmpty
        }

        # The pinned function never passes -EnableException on, so its nested Get-DbaDatabase warns and goes on, with or without it.
        It "still warns and goes on under -EnableException, as the pinned function does" -Tag "NativeChecklist:enable-exception" {
            $mirrorUnreachableErrors = @()
            $mirrorStream = @(Get-DbaDbMirror -SqlInstance $mirrorBadInstance, $mirrorPrincipal -Database $mirrorDb2 -EnableException -ErrorVariable mirrorUnreachableErrors 3>&1)
            $mirrorStream.Count | Should -Be 2
            $mirrorStream[0] | Should -BeOfType System.Management.Automation.WarningRecord
            $mirrorStream[1].Name | Should -BeExactly $mirrorDb2
            # The same one nested record reaches -ErrorVariable, as this switch never reaches the nested call.
            $mirrorUnreachableErrors = @($mirrorUnreachableErrors)
            $mirrorUnreachableErrors.Count | Should -Be 1
            $mirrorUnreachableErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
        }

        It "ignores -ErrorAction Stop at an instance it cannot reach, as the pinned function does" {
            $mirrorRows = @(Get-DbaDbMirror -SqlInstance $mirrorBadInstance, $mirrorPrincipal -Database $mirrorDb2 -EnableException:$false -ErrorAction Stop -WarningAction SilentlyContinue)
            $mirrorRows.Name | Should -BeExactly $mirrorDb2
        }

        # Correction witness-rows. A witness holds no copy of the database, so -Database leaves no local database here and the row still comes.
        It "writes one object for a witness row, with the sixteen pinned names" {
            $mirrorServers.Witness.Query("SELECT COUNT(*) AS n FROM sys.databases WHERE name = N'$mirrorDb2';").n | Should -Be 0
            $mirrorWitnessRow = @($mirrorServers.Witness.Query($mirrorWitnessQuery) | Where-Object database_name -eq $mirrorDb2)[0]
            $mirrorRows = @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database $mirrorDb2)
            $mirrorRows.Count | Should -Be 1
            $mirrorRows[0].GetType().FullName | Should -BeExactly "System.Management.Automation.PSCustomObject"
            ($mirrorRows[0].PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,MirroringSafetyLevel,MirroringStatus,MirroringPartner,MirroringPartnerInstance,MirroringFailoverLogSequenceNumber,MirroringID,MirroringRedoQueueMaxSize,MirroringRoleSequence,MirroringSafetySequence,MirroringTimeout,MirroringWitness,MirroringWitnessStatus"
            $mirrorRows[0].SqlInstance | Should -Be $mirrorServers.Witness.DomainInstanceName
            $mirrorRows[0].Name | Should -BeExactly $mirrorDb2
            $mirrorRows[0].MirroringPartner | Should -BeExactly $mirrorWitnessRow.principal_server_name
            $mirrorRows[0].MirroringSafetyLevel | Should -BeExactly $mirrorWitnessRow.safety_level_desc
            $mirrorRows[0].MirroringWitnessStatus | Should -BeExactly "Synchronized"
            foreach ($mirrorEmpty in "MirroringStatus", "MirroringPartnerInstance", "MirroringFailoverLogSequenceNumber", "MirroringID", "MirroringRedoQueueMaxSize", "MirroringRoleSequence", "MirroringSafetySequence", "MirroringTimeout", "MirroringWitness") {
                $mirrorRows[0].$mirrorEmpty | Should -BeNullOrEmpty -Because $mirrorEmpty
            }
            @(Get-DbaDbMirror -SqlInstance $mirrorWitness | Where-Object Name -eq $mirrorDb2).Count | Should -Be 1
            @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database $mirrorDb2.ToUpperInvariant()).Name | Should -BeExactly $mirrorDb2
            @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database "dbatoolsci_mirror2_*$mirrorSuffix").Name | Should -BeExactly $mirrorDb2
        }

        It "writes no witness row for a database -Database does not select" {
            @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database master).Count | Should -Be 0
        }

        # Correction witness-overlay. This database stays until AfterAll, so the next test also runs beside it.
        It "writes the witness row and no database for a database of that name on the witness server" {
            $null = $mirrorServers.Witness.Query("CREATE DATABASE [$mirrorDb2];")
            $mirrorRows = @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database $mirrorDb2)
            @($mirrorRows | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.Database] }).Count | Should -Be 0
            $mirrorRows.Count | Should -Be 1
            $mirrorRows[0].MirroringWitnessStatus | Should -BeExactly "Synchronized"
            $mirrorRows[0].MirroringID | Should -BeNullOrEmpty
        }

        # Correction witness-out-of-sync. Last in this Context: it suspends the witnessed session and resumes it.
        It "reports OutOfSync for a witness row whose partners are not synchronized" {
            $null = $mirrorServers.Principal.Query("ALTER DATABASE [$mirrorDb2] SET PARTNER SUSPEND;")
            try {
                for ($mirrorAttempt = 0; $mirrorAttempt -lt 30; $mirrorAttempt++) {
                    $mirrorWitnessRow = @($mirrorServers.Witness.Query($mirrorWitnessQuery) | Where-Object database_name -eq $mirrorDb2)[0]
                    if ($mirrorWitnessRow.partner_sync_state -eq 6) { break }
                    Start-Sleep -Seconds 2
                }
                $mirrorWitnessRow.partner_sync_state | Should -Be 6
                $mirrorRows = @(Get-DbaDbMirror -SqlInstance $mirrorWitness -Database $mirrorDb2 | Where-Object { $PSItem -isnot [Microsoft.SqlServer.Management.Smo.Database] })
                $mirrorRows.Count | Should -Be 1
                $mirrorRows[0].MirroringWitnessStatus | Should -BeExactly "OutOfSync"
            } finally {
                $null = $mirrorServers.Principal.Query("ALTER DATABASE [$mirrorDb2] SET PARTNER RESUME;")
            }
        }
    }
}

Describe "Native Get-DbaDbMirror over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        # The login instance holds no mirrored database, so a read that worked is a read with no warning.
        It "works with -SqlCredential" {
            @(Get-DbaDbMirror -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException 2>&1 3>&1).Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginStream = @(Get-DbaDbMirror -SqlInstance $loginInstance -EnableException:$false 3>&1)
            $loginStream.Count | Should -Be 1
            $loginStream[0] | Should -BeOfType System.Management.Automation.WarningRecord
            "$($loginStream[0])" | Should -BeLike "*Get-DbaDatabase*Failure | *Login failed*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $loginStream = @(Get-DbaDbMirror -SqlInstance $loginInstance -EnableException 3>&1)
            $loginStream.Count | Should -Be 1
            $loginStream[0] | Should -BeOfType System.Management.Automation.WarningRecord
            "$($loginStream[0])" | Should -BeLike "*Get-DbaDatabase*Failure | *Login failed*"
        }
    }

    Context "A login denied the witness view" {
        BeforeAll {
            # The login instance is shared by the lanes, so the login is unique per leg and run.
            $deniedAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $deniedLogin = "dbatoolsci_mirrordeny_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
            $deniedSecret = "Mrr-$([guid]::NewGuid().ToString('N'))"
            $deniedSecure = ConvertTo-SecureString -String $deniedSecret -AsPlainText -Force
            $deniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $deniedLogin, $deniedSecure
            $null = $deniedAdmin.Query("CREATE LOGIN [$deniedLogin] WITH PASSWORD = N'$deniedSecret', CHECK_POLICY = OFF;")
            $null = $deniedAdmin.Query("CREATE USER [$deniedLogin] FOR LOGIN [$deniedLogin]; DENY SELECT ON OBJECT::sys.database_mirroring_witnesses TO [$deniedLogin];", "master")
            $splatDenied = @{
                SqlInstance   = $TestConfig.InstanceSqlLogin
                SqlCredential = $deniedCred
            }
        }

        AfterAll {
            $null = $deniedAdmin.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$deniedLogin'; EXEC sys.sp_executesql @kill;")
            $null = $deniedAdmin.Query("IF DATABASE_PRINCIPAL_ID(N'$deniedLogin') IS NOT NULL DROP USER [$deniedLogin];", "master")
            $null = $deniedAdmin.Query("IF SUSER_ID(N'$deniedLogin') IS NOT NULL DROP LOGIN [$deniedLogin];")
        }

        # The operator kept this when approving the witness rows (2026-11-02): a failed witness read goes on with no record, as the pin's catch does.
        It "passes over a witness view it cannot read, with no record, as the pinned function does" {
            $deniedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $deniedCred -EnableException
            { $deniedServer.Query("SELECT database_name FROM master.sys.database_mirroring_witnesses;") } | Should -Throw "*database_mirroring_witnesses*"
            foreach ($deniedThrowing in $false, $true) {
                @(Get-DbaDbMirror @splatDenied -EnableException:$deniedThrowing 2>&1 3>&1).Count | Should -Be 0
            }
        }
    }
}

Describe "Native Get-DbaDbMirror on Azure SQL Database" -Tag IntegrationTests {
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

    # Database mirroring does not exist in Azure SQL Database:
    # https://learn.microsoft.com/azure/azure-sql/database/features-comparison#features-of-sql-database-and-sql-managed-instance
    It "refuses Azure SQL Database, which has no database mirroring" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = $null
        @(Get-DbaDbMirror -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
        $azureWarnings.Count | Should -Be 1
        "$($azureWarnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        { Get-DbaDbMirror -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
