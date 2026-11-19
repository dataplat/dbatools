#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaSuspectPage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.
# NativeChecklist: azure-sqldb N/A -- the command reads msdb.dbo.suspect_pages; Azure SQL Database has no msdb for users and supports no cross-database three-part names to it.

Describe "Native suspect page behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeSuspectDatabaseCreated = $false
        $nativeSuspectRowsInserted = $false
        $nativeSuspectServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSuspectDatabaseName = "native_suspect_" + [Guid]::NewGuid().ToString("N")
        $nativeSuspectDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSuspectServer, $nativeSuspectDatabaseName
        $nativeSuspectDatabase.Create()
        $nativeSuspectDatabaseCreated = $true
        $nativeSuspectDatabaseId = [int]$nativeSuspectDatabase.ID

        # Rows are written straight into msdb.dbo.suspect_pages (sysadmin may insert there), so the
        # fixture needs no corruption. The page ids are unique to this run; every assertion and the
        # cleanup select only these pages of this database.
        $nativeSuspectPageBase = [long](Get-Random -Minimum 100000000 -Maximum 900000000)
        $nativeSuspectPages = @($nativeSuspectPageBase, ($nativeSuspectPageBase + 1), ($nativeSuspectPageBase + 2))
        $nativeSuspectExpected = @{
            "$($nativeSuspectPages[0])" = @{ FileId = 1; EventType = "823 or 824"; ErrorCount = 3 }
            "$($nativeSuspectPages[1])" = @{ FileId = 1; EventType = "Bad Checksum"; ErrorCount = 1 }
            "$($nativeSuspectPages[2])" = @{ FileId = 2; EventType = "Deallocated (DBCC)"; ErrorCount = 7 }
        }
        $nativeSuspectInsert = "INSERT INTO msdb.dbo.suspect_pages (database_id, file_id, page_id, event_type, error_count, last_update_date) VALUES " +
            "($nativeSuspectDatabaseId, 1, $($nativeSuspectPages[0]), 1, 3, '2026-01-02T03:04:05'), " +
            "($nativeSuspectDatabaseId, 1, $($nativeSuspectPages[1]), 2, 1, '2026-01-02T03:04:05'), " +
            "($nativeSuspectDatabaseId, 2, $($nativeSuspectPages[2]), 7, 7, '2026-01-02T03:04:05')"
        $nativeSuspectRowsInserted = $true
        $null = $nativeSuspectServer.ConnectionContext.ExecuteNonQuery($nativeSuspectInsert)
        $nativeSuspectPropertyOrder = "ComputerName,InstanceName,SqlInstance,Database,FileId,PageId,EventType,ErrorCount,LastUpdateDate"

        function Get-NativeSuspectFixtureRow {
            param($Rows)
            @($Rows | Where-Object { $PSItem.Database -eq $nativeSuspectDatabaseName -and $nativeSuspectPages -contains $PSItem.PageId })
        }
    }

    AfterAll {
        if ($nativeSuspectRowsInserted) {
            $nativeSuspectDelete = "DELETE FROM msdb.dbo.suspect_pages WHERE database_id = $nativeSuspectDatabaseId AND page_id IN ($($nativeSuspectPages -join ', '))"
            $null = $nativeSuspectServer.ConnectionContext.ExecuteNonQuery($nativeSuspectDelete)
        }
        if ($nativeSuspectDatabaseCreated) {
            $splatRemoveNativeSuspectDatabase = @{
                SqlInstance     = $nativeSuspectServer
                Database        = $nativeSuspectDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeSuspectDatabase
        }
    }

    It "returns the fixture rows as ordered PSCustomObjects with typed values and mapped event types" {
        $splatNativeSuspectRead = @{
            SqlInstance     = $nativeSuspectServer
            Database        = $nativeSuspectDatabaseName
            EnableException = $true
        }
        $nativeSuspectRows = Get-NativeSuspectFixtureRow -Rows (Get-DbaSuspectPage @splatNativeSuspectRead)
        $nativeSuspectRows.Count | Should -Be 3
        foreach ($nativeSuspectRow in $nativeSuspectRows) {
            $nativeSuspectRow | Should -BeOfType System.Management.Automation.PSCustomObject
            ($nativeSuspectRow.PSObject.Properties.Name -join ",") | Should -BeExactly $nativeSuspectPropertyOrder
            $nativeSuspectRow.PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
            $nativeSuspectRow.ComputerName | Should -BeExactly $nativeSuspectServer.ComputerName
            $nativeSuspectRow.InstanceName | Should -BeExactly $nativeSuspectServer.ServiceName
            $nativeSuspectRow.SqlInstance | Should -BeExactly $nativeSuspectServer.DomainInstanceName
            $nativeSuspectRow.Database | Should -BeExactly $nativeSuspectDatabaseName
            $nativeSuspectRow.FileId | Should -BeOfType System.Int32
            $nativeSuspectRow.PageId | Should -BeOfType System.Int64
            $nativeSuspectRow.ErrorCount | Should -BeOfType System.Int32
            $nativeSuspectRow.LastUpdateDate | Should -BeOfType System.DateTime
            $nativeSuspectRow.LastUpdateDate | Should -Be (New-Object System.DateTime -ArgumentList 2026, 1, 2, 3, 4, 5)
            $nativeSuspectWanted = $nativeSuspectExpected["$($nativeSuspectRow.PageId)"]
            $nativeSuspectRow.FileId | Should -Be $nativeSuspectWanted.FileId
            $nativeSuspectRow.EventType | Should -BeExactly $nativeSuspectWanted.EventType
            $nativeSuspectRow.ErrorCount | Should -Be $nativeSuspectWanted.ErrorCount
        }
    }

    It "filters with literal case-insensitive equality, positional binding and truthiness" {
        $nativeSuspectUpper = Get-NativeSuspectFixtureRow -Rows (Get-DbaSuspectPage $nativeSuspectServer $nativeSuspectDatabaseName.ToUpperInvariant() -EnableException)
        $nativeSuspectUpper.Count | Should -Be 3

        $nativeSuspectAll = @(Get-DbaSuspectPage -SqlInstance $nativeSuspectServer -EnableException)
        (Get-NativeSuspectFixtureRow -Rows $nativeSuspectAll).Count | Should -Be 3
        $nativeSuspectEmptyFilter = @(Get-DbaSuspectPage -SqlInstance $nativeSuspectServer -Database "" -EnableException)
        (Get-NativeSuspectFixtureRow -Rows $nativeSuspectEmptyFilter).Count | Should -Be 3

        @(Get-DbaSuspectPage -SqlInstance $nativeSuspectServer -Database "native_suspect_*" -EnableException).Count | Should -Be 0
        $nativeSuspectOther = @(Get-DbaSuspectPage -SqlInstance $nativeSuspectServer -Database ($nativeSuspectDatabaseName + "_other") -EnableException)
        $nativeSuspectOther.Count | Should -Be 0
    }

    It "returns the rows once for every piped instance record" -Tag "NativeChecklist:pipeline-multiple" {
        $nativeSuspectPiped = Get-NativeSuspectFixtureRow -Rows (@($nativeSuspectServer, $nativeSuspectServer) | Get-DbaSuspectPage -Database $nativeSuspectDatabaseName -EnableException)
        $nativeSuspectPiped.Count | Should -Be 6
        @($nativeSuspectPiped | Group-Object PageId | Where-Object Count -ne 2).Count | Should -Be 0
    }

    Context "with an unreachable instance" {
        BeforeAll {
            $nativeSuspectSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
            $nativeSuspectListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            $nativeSuspectListener.Start()
            $nativeSuspectFailedInstance = "127.0.0.1," + $nativeSuspectListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
        }

        AfterAll {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeSuspectSavedTimeout
            $nativeSuspectListener.Stop()
        }

        It "warns and continues for a failing instance when EnableException is false" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $nativeSuspectWarnings = @()
            $splatNativeSuspectContinue = @{
                SqlInstance     = $nativeSuspectServer, $nativeSuspectFailedInstance
                Database        = $nativeSuspectDatabaseName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeSuspectWarnings"
            }
            $nativeSuspectContinued = Get-NativeSuspectFixtureRow -Rows (Get-DbaSuspectPage @splatNativeSuspectContinue)
            $nativeSuspectContinued.Count | Should -Be 3
            @($nativeSuspectContinued | Where-Object SqlInstance -ne $nativeSuspectServer.DomainInstanceName).Count | Should -Be 0
            $nativeSuspectWarnings.Count | Should -Be 1
            ($nativeSuspectWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "terminates on the failing piped instance with EnableException while keeping earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            $nativeSuspectEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeSuspectCaught = $null
            try {
                @($nativeSuspectServer, $nativeSuspectFailedInstance, $nativeSuspectServer) |
                    Get-DbaSuspectPage -Database $nativeSuspectDatabaseName -EnableException |
                    ForEach-Object { $nativeSuspectEarlier.Add($PSItem) }
            } catch {
                $nativeSuspectCaught = $PSItem
            }
            (Get-NativeSuspectFixtureRow -Rows $nativeSuspectEarlier).Count | Should -Be 3
            $nativeSuspectCaught | Should -Not -BeNullOrEmpty
            $nativeSuspectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeSuspectCaught.TargetObject | Should -Be $nativeSuspectFailedInstance
        }

        It "does not repeat an earlier record's rows after a piped instance fails to connect" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $nativeSuspectWarnings = @()
            $splatNativeSuspectPipedFailure = @{
                Database        = $nativeSuspectDatabaseName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeSuspectWarnings"
            }
            $nativeSuspectPipedRows = Get-NativeSuspectFixtureRow -Rows (@($nativeSuspectServer, $nativeSuspectFailedInstance) | Get-DbaSuspectPage @splatNativeSuspectPipedFailure)
            $nativeSuspectWarnings.Count | Should -Be 1
            $nativeSuspectPipedRows.Count | Should -Be 3
        }
    }

    It "returns the rows of every instance passed to -SqlInstance, not only the last" {
        $nativeSuspectBoth = Get-NativeSuspectFixtureRow -Rows (Get-DbaSuspectPage -SqlInstance $nativeSuspectServer, $nativeSuspectServer -Database $nativeSuspectDatabaseName -EnableException)
        $nativeSuspectBoth.Count | Should -Be 6
        @($nativeSuspectBoth | Group-Object PageId | Where-Object Count -ne 2).Count | Should -Be 0
    }
}

Describe "Native Get-DbaSuspectPage over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared; only this database's unique page is written.
            $loginDbName = "native_suspect_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabaseId = [int]$loginDatabase.ID
            $loginPage = [long](Get-Random -Minimum 100000000 -Maximum 900000000)
            $null = $loginServer.ConnectionContext.ExecuteNonQuery("INSERT INTO msdb.dbo.suspect_pages (database_id, file_id, page_id, event_type, error_count, last_update_date) VALUES ($loginDatabaseId, 1, $loginPage, 2, 1, '2026-01-02T03:04:05');")
        }
        AfterAll {
            if ($loginServer) {
                $null = $loginServer.ConnectionContext.ExecuteNonQuery("DELETE FROM msdb.dbo.suspect_pages WHERE database_id = $loginDatabaseId AND page_id = $loginPage;")
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginSuspect = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaSuspectPage @splatLoginSuspect | Where-Object PageId -eq $loginPage)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Database | Should -BeExactly $loginDbName
            $loginRows[0].EventType | Should -BeExactly "Bad Checksum"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaSuspectPage @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaSuspectPage -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
