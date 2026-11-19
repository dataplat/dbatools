#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbSnapshot",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database has no database snapshots (CREATE DATABASE ... AS SNAPSHOT OF is SQL Server only), and the command's disk-usage query uses fn_virtualfilestats, which Azure SQL Database does not support (Microsoft Learn, T-SQL differences).

Describe "Native database snapshot behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeSnapCreated = New-Object "System.Collections.Generic.List[string]"
        $nativeSnapServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSnapPrefix = "native_snap_" + [Guid]::NewGuid().ToString("N")
        # Name the snapshots against their bases so name order and base order disagree.
        $nativeSnapBaseA = $nativeSnapPrefix + "_a"
        $nativeSnapBaseZ = $nativeSnapPrefix + "_z"
        $nativeSnapOfA1 = $nativeSnapPrefix + "_z_s1"
        $nativeSnapOfA2 = $nativeSnapPrefix + "_z_s2"
        $nativeSnapOfZ = $nativeSnapPrefix + "_a_s1"
        foreach ($nativeSnapBase in $nativeSnapBaseA, $nativeSnapBaseZ) {
            $nativeSnapNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSnapServer, $nativeSnapBase
            $nativeSnapNew.Create()
            $nativeSnapCreated.Add($nativeSnapBase)
        }
        # An SMO-created database keeps the empty FileGroups collection it was scripted with, so the snapshot
        # files come from New-DbaDbSnapshot, as in the pinned test, after a refresh shows the new bases.
        $nativeSnapServer.Databases.Refresh()
        foreach ($nativeSnapPair in @(@($nativeSnapBaseA, $nativeSnapOfA1), @($nativeSnapBaseA, $nativeSnapOfA2), @($nativeSnapBaseZ, $nativeSnapOfZ))) {
            $splatNewNativeSnap = @{
                SqlInstance     = $nativeSnapServer
                Database        = $nativeSnapPair[0]
                Name            = $nativeSnapPair[1]
                EnableException = $true
                WarningAction   = "SilentlyContinue"
            }
            $null = New-DbaDbSnapshot @splatNewNativeSnap
            $nativeSnapCreated.Insert(0, $nativeSnapPair[1])
        }
        $nativeSnapServer.Databases.Refresh()
        $nativeSnapDisplay = "ComputerName,InstanceName,SqlInstance,Name,SnapshotOf,CreateDate,DiskUsage"
    }

    AfterAll {
        # Snapshots were inserted first, so they drop before their bases.
        foreach ($nativeSnapName in $nativeSnapCreated) {
            $nativeSnapServer.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$nativeSnapName') IS NOT NULL DROP DATABASE [$nativeSnapName];")
        }
    }

    It "decorates every snapshot and restores the caller's database context across repeated pipeline records" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeSnapPrevious = $nativeSnapServer.ConnectionContext.CurrentDatabase
        $nativeSnapRows = @(@($nativeSnapServer, $nativeSnapServer) | Get-DbaDbSnapshot -Database $nativeSnapBaseA -EnableException)
        $nativeSnapServer.ConnectionContext.CurrentDatabase | Should -BeExactly $nativeSnapPrevious
        $nativeSnapRows.Count | Should -Be 4
        ($nativeSnapRows.Name -join ",") | Should -BeExactly "$nativeSnapOfA1,$nativeSnapOfA2,$nativeSnapOfA1,$nativeSnapOfA2"
        foreach ($nativeSnapRow in $nativeSnapRows) {
            $nativeSnapRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $nativeSnapRow.SnapshotOf | Should -BeExactly $nativeSnapBaseA
            $nativeSnapRow.ComputerName | Should -BeExactly $nativeSnapServer.ComputerName
            $nativeSnapRow.InstanceName | Should -BeExactly $nativeSnapServer.ServiceName
            $nativeSnapRow.SqlInstance | Should -BeExactly $nativeSnapServer.DomainInstanceName
            $nativeSnapRow.DiskUsage | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeSnapRow.DiskUsage.Byte | Should -BeGreaterThan 0
            ($nativeSnapRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeSnapDisplay
            @($nativeSnapRow.PSObject.Properties | Where-Object Name -eq "DiskUsage").Count | Should -Be 1
        }
    }

    It "sorts by base and snapshot name only when neither Database nor Snapshot is given" {
        $nativeSnapAll = @(Get-DbaDbSnapshot -SqlInstance $nativeSnapServer -EnableException | Where-Object Name -like "$nativeSnapPrefix*")
        ($nativeSnapAll.Name -join ",") | Should -BeExactly "$nativeSnapOfA1,$nativeSnapOfA2,$nativeSnapOfZ"
        $nativeSnapFiltered = @(Get-DbaDbSnapshot -SqlInstance $nativeSnapServer -Database $nativeSnapBaseZ, $nativeSnapBaseA -EnableException)
        ($nativeSnapFiltered.Name -join ",") | Should -BeExactly "$nativeSnapOfZ,$nativeSnapOfA1,$nativeSnapOfA2"
    }

    It "applies literal case-insensitive base and snapshot filters with exclusions taking precedence" {
        $splatNativeSnapFilter = @{
            SqlInstance     = $nativeSnapServer
            EnableException = $true
        }
        $nativeSnapByName = @(Get-DbaDbSnapshot @splatNativeSnapFilter -Snapshot $nativeSnapOfA2.ToUpperInvariant())
        $nativeSnapByName.Count | Should -Be 1
        $nativeSnapByName[0].SnapshotOf | Should -BeExactly $nativeSnapBaseA
        $nativeSnapExcluded = @(Get-DbaDbSnapshot @splatNativeSnapFilter -Database $nativeSnapBaseA.ToUpperInvariant() -ExcludeSnapshot $nativeSnapOfA1)
        ($nativeSnapExcluded.Name -join ",") | Should -BeExactly $nativeSnapOfA2
        @(Get-DbaDbSnapshot @splatNativeSnapFilter -Database $nativeSnapBaseA, $nativeSnapBaseZ -ExcludeDatabase $nativeSnapBaseA).Name | Should -BeExactly $nativeSnapOfZ
        @(Get-DbaDbSnapshot @splatNativeSnapFilter -Snapshot "$nativeSnapPrefix*").Count | Should -Be 0
    }

    It "continues after connection failure unless EnableException terminates while retaining earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeSnapSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeSnapListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeSnapListener.Start()
            $nativeSnapFailedInstance = "127.0.0.1," + $nativeSnapListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeSnapWarnings = @()
            $nativeSnapPreviousErrors = @($global:Error)
            $splatNativeSnapFailure = @{
                Snapshot        = $nativeSnapOfZ
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeSnapWarnings"
            }
            $nativeSnapContinued = @(@($nativeSnapServer, $nativeSnapFailedInstance, $nativeSnapServer) | Get-DbaDbSnapshot @splatNativeSnapFailure)
            ($nativeSnapContinued.Name -join ",") | Should -BeExactly "$nativeSnapOfZ,$nativeSnapOfZ"
            ($nativeSnapWarnings -join " ") | Should -BeLike "*Failure*"
            $nativeSnapConnectionError = $global:Error | Where-Object {
                $nativeSnapPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbSnapshot*"
            } | Select-Object -First 1
            $nativeSnapConnectionError | Should -Not -BeNullOrEmpty
            $nativeSnapConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"

            $nativeSnapEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeSnapCaught = $null
            $splatNativeSnapFailure.EnableException = $true
            try {
                @($nativeSnapServer, $nativeSnapFailedInstance, $nativeSnapServer) |
                    Get-DbaDbSnapshot @splatNativeSnapFailure |
                    ForEach-Object { $nativeSnapEarlier.Add($PSItem) }
            } catch {
                $nativeSnapCaught = $PSItem
            }
            $nativeSnapEarlier.Count | Should -Be 1
            $nativeSnapEarlier[0].Name | Should -BeExactly $nativeSnapOfZ
            $nativeSnapCaught | Should -Not -BeNullOrEmpty
            $nativeSnapCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeSnapCaught.TargetObject | Should -Be $nativeSnapFailedInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeSnapSavedTimeout
            $nativeSnapListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbSnapshot numeric database and snapshot selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeSnapNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSnapNumber = Get-Random -Minimum 100000000 -Maximum 899999999
        $nativeSnapNumberSnapshot = $nativeSnapNumber + 1
        # Base 0N gets snapshot 0M and base N gets snapshot M, so a numeric value matches both names of a pair.
        $nativeSnapNumberBases = @("0$nativeSnapNumber", "$nativeSnapNumber")
        $nativeSnapNumberSnapshots = @("0$nativeSnapNumberSnapshot", "$nativeSnapNumberSnapshot")
        $nativeSnapNumberCreated = New-Object "System.Collections.Generic.List[string]"
        for ($nativeSnapNumberIndex = 0; $nativeSnapNumberIndex -lt 2; $nativeSnapNumberIndex++) {
            $nativeSnapNumberBase = $nativeSnapNumberBases[$nativeSnapNumberIndex]
            $nativeSnapNumberName = $nativeSnapNumberSnapshots[$nativeSnapNumberIndex]
            $nativeSnapNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSnapNumberServer, $nativeSnapNumberBase
            $nativeSnapNumberDatabase.Create()
            $nativeSnapNumberCreated.Add($nativeSnapNumberBase)
            # New-DbaDbSnapshot supplies the snapshot files; the SMO-created base has no loaded FileGroups.
            $nativeSnapNumberServer.Databases.Refresh()
            $splatNewNativeSnapNumber = @{
                SqlInstance     = $nativeSnapNumberServer
                Database        = $nativeSnapNumberBase
                Name            = $nativeSnapNumberName
                EnableException = $true
                WarningAction   = "SilentlyContinue"
            }
            $null = New-DbaDbSnapshot @splatNewNativeSnapNumber
            $nativeSnapNumberCreated.Insert(0, $nativeSnapNumberName)
        }
        $nativeSnapNumberServer.Databases.Refresh()
        $nativeSnapNumberExpected = ($nativeSnapNumberSnapshots | Sort-Object) -join ","
    }

    AfterAll {
        # Snapshots were inserted first, so they drop before their bases.
        foreach ($nativeSnapNumberDrop in $nativeSnapNumberCreated) {
            $nativeSnapNumberServer.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$nativeSnapNumberDrop') IS NOT NULL DROP DATABASE [$nativeSnapNumberDrop];")
        }
    }

    It "converts each base name to the type of a numeric Database or ExcludeDatabase value, as -contains does" {
        $splatNativeSnapNumberInclude = @{
            SqlInstance     = $nativeSnapNumberServer
            Database        = [int]$nativeSnapNumber
            EnableException = $true
        }
        $nativeSnapNumberIncluded = @(Get-DbaDbSnapshot @splatNativeSnapNumberInclude)
        (($nativeSnapNumberIncluded.Name | Sort-Object) -join ",") | Should -BeExactly $nativeSnapNumberExpected

        $splatNativeSnapNumberExclude = @{
            SqlInstance     = $nativeSnapNumberServer
            Database        = $nativeSnapNumberBases
            ExcludeDatabase = [int]$nativeSnapNumber
            EnableException = $true
        }
        @(Get-DbaDbSnapshot @splatNativeSnapNumberExclude).Count | Should -Be 0
    }

    It "converts each snapshot name to the type of a numeric Snapshot or ExcludeSnapshot value, as -contains does" {
        $splatNativeSnapNumberSnapshot = @{
            SqlInstance     = $nativeSnapNumberServer
            Snapshot        = [int]$nativeSnapNumberSnapshot
            EnableException = $true
        }
        $nativeSnapNumberSelected = @(Get-DbaDbSnapshot @splatNativeSnapNumberSnapshot)
        (($nativeSnapNumberSelected.Name | Sort-Object) -join ",") | Should -BeExactly $nativeSnapNumberExpected

        $splatNativeSnapNumberExcludeSnapshot = @{
            SqlInstance     = $nativeSnapNumberServer
            Database        = $nativeSnapNumberBases
            ExcludeSnapshot = [int]$nativeSnapNumberSnapshot
            EnableException = $true
        }
        @(Get-DbaDbSnapshot @splatNativeSnapNumberExcludeSnapshot).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbSnapshot over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginBaseName = "native_snap_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginSnapName = $loginBaseName + "_s1"
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginBaseName
            $loginDatabase.Create()
            $loginServer.Databases.Refresh()
            $splatNewLoginSnap = @{
                SqlInstance     = $loginServer
                Database        = $loginBaseName
                Name            = $loginSnapName
                EnableException = $true
                WarningAction   = "SilentlyContinue"
            }
            $null = New-DbaDbSnapshot @splatNewLoginSnap
        }
        AfterAll {
            if ($loginServer) {
                # The snapshot drops before its base; KillDatabase ends the base's pooled connections.
                $loginServer.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$loginSnapName') IS NOT NULL DROP DATABASE [$loginSnapName];")
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginBaseName]) {
                    $loginServer.KillDatabase($loginBaseName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginSnap = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginBaseName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbSnapshot @splatLoginSnap)
            ($loginRows.Name -join ",") | Should -BeExactly $loginSnapName
            $loginRows[0].SnapshotOf | Should -BeExactly $loginBaseName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginBaseName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbSnapshot @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbSnapshot -SqlInstance $loginInstance -Database $loginBaseName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
