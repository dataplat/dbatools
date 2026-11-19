#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Add-DbaDbMirrorMonitor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Add-DbaDbMirrorMonitor" -Tag IntegrationTests {
    BeforeAll {
        $nativeMirrorServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeMirrorCleanup = "IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Database Mirroring Monitor Job') EXEC msdb.dbo.sp_dbmmonitordropmonitoring;"
    }

    BeforeEach {
        $null = $nativeMirrorServer.ConnectionContext.ExecuteNonQuery($nativeMirrorCleanup)
    }

    AfterEach {
        $null = $nativeMirrorServer.ConnectionContext.ExecuteNonQuery($nativeMirrorCleanup)
    }

    It "creates the monitor and emits only the four-property status object" -Tag "NativeChecklist:switch-false" {
        $splatNativeMonitor = @{
            SqlInstance     = $nativeMirrorServer
            Confirm         = $false
            WhatIf          = $false
            EnableException = $true
        }
        $nativeMirrorResults = @(Add-DbaDbMirrorMonitor @splatNativeMonitor)
        $nativeMirrorResults.Count | Should -Be 1
        $nativeMirrorResults[0].MonitorStatus | Should -BeExactly "Added"
        ($nativeMirrorResults[0].PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,MonitorStatus"
        $nativeMirrorResults[0].SqlInstance | Should -Not -BeNullOrEmpty
        $nativeMirrorJobs = $nativeMirrorServer.ConnectionContext.ExecuteWithResults("SELECT COUNT(*) AS JobCount FROM msdb.dbo.sysjobs WHERE name = N'Database Mirroring Monitor Job';")
        $nativeMirrorJobs.Tables[0].Rows[0].JobCount | Should -Be 1
    }

    It "performs no change and emits no result under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $splatNativeMonitor = @{
            SqlInstance     = $nativeMirrorServer
            WhatIf          = $true
            Confirm         = $false
            EnableException = $true
        }
        @(Add-DbaDbMirrorMonitor @splatNativeMonitor).Count | Should -Be 0
        $nativeMirrorJobs = $nativeMirrorServer.ConnectionContext.ExecuteWithResults("SELECT COUNT(*) AS JobCount FROM msdb.dbo.sysjobs WHERE name = N'Database Mirroring Monitor Job';")
        $nativeMirrorJobs.Tables[0].Rows[0].JobCount | Should -Be 0
    }

    It "streams successful pipeline records around a failed instance" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $splatNativeMonitor = @{
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeMirrorWarnings"
        }
        $nativeMirrorResults = @(& {
                $nativeMirrorServer
                $null = $nativeMirrorServer.ConnectionContext.ExecuteNonQuery($nativeMirrorCleanup)
                "tcp:127.0.0.1,1"
                $nativeMirrorServer
            } | Add-DbaDbMirrorMonitor @splatNativeMonitor)
        $nativeMirrorResults.Count | Should -Be 2
        @($nativeMirrorResults | Where-Object MonitorStatus -ne "Added").Count | Should -Be 0
        @($nativeMirrorWarnings).Count | Should -Be 1
        ($nativeMirrorWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "terminates at a failed connection with EnableException after retaining earlier output" -Tag "NativeChecklist:enable-exception", "NativeChecklist:multi-instance-failure" {
        $nativeMirrorSeen = New-Object System.Collections.ArrayList
        $splatNativeMonitor = @{
            Confirm         = $false
            EnableException = $true
        }
        $nativeMirrorError = $null
        try {
            @($nativeMirrorServer, "tcp:127.0.0.1,1", $nativeMirrorServer) |
                Add-DbaDbMirrorMonitor @splatNativeMonitor |
                ForEach-Object { $null = $nativeMirrorSeen.Add($PSItem) }
        } catch {
            $nativeMirrorError = $PSItem
        }
        $nativeMirrorError | Should -Not -BeNullOrEmpty
        $nativeMirrorError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $nativeMirrorSeen.Count | Should -Be 1
        $nativeMirrorSeen[0].MonitorStatus | Should -BeExactly "Added"
    }
}

Describe "Native Add-DbaDbMirrorMonitor SQL authentication" -Tag IntegrationTests, "NativeChecklist:sql-login" {
    It "connects with the SQL credential before processing WhatIf" {
        # The monitor has one fixed name per instance. WhatIf exercises the command's
        # connection without changing the singleton shared by concurrent test legs.
        $splatLoginMonitor = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            WhatIf = $true
            Confirm = $false
            EnableException = $true
        }
        @(Add-DbaDbMirrorMonitor @splatLoginMonitor).Count | Should -Be 0
    }

    It "warns without output when the SQL credential is omitted" {
        $nativeLoginWarnings = @()
        $splatLoginDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            WhatIf = $true
            Confirm = $false
            EnableException = $false
            WarningAction = 'SilentlyContinue'
            WarningVariable = 'nativeLoginWarnings'
        }
        @(Add-DbaDbMirrorMonitor @splatLoginDenied).Count | Should -Be 0
        $nativeLoginWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when the SQL credential is omitted" {
        # Pinned public/Add-DbaDbMirrorMonitor.ps1:68-72 catches Connect-DbaInstance directly.
        # Pinned private/functions/flowcontrol/Stop-Function.ps1:200-262 throws the original error under EnableException.
        { Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSqlLogin -WhatIf -Confirm:$false -EnableException } | Should -Throw
    }
}

Describe "Add-DbaDbMirrorMonitor Azure refusal" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    It "refuses Azure database mirroring monitoring with the canonical message" {
        # SQL Agent and database mirroring are absent in Azure SQL Database:
        # https://learn.microsoft.com/azure/azure-sql/database/features-comparison#features-of-sql-database-and-sql-managed-instance
        $azureMirrorServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureMirrorServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                }
                catch {
                    $errorDetail = $_.Exception
                    $resuming = $false
                    while ($errorDetail) {
                        if ($errorDetail.Number -in 40613, -2 -or $errorDetail -is [System.TimeoutException]) { $resuming = $true }
                        $errorDetail = $errorDetail.InnerException
                    }
                    if (-not $resuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureMirrorServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Add-DbaDbMirrorMonitor -SqlInstance $azureMirrorServer -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -BeLike '*Azure SQL Database not supported*'
            { Add-DbaDbMirrorMonitor -SqlInstance $azureMirrorServer -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        }
        finally {
            if ($azureMirrorServer) { $azureMirrorServer.ConnectionContext.Disconnect() }
        }
    }
}
