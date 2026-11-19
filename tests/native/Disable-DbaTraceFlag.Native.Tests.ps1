#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaTraceFlag",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Disable-DbaTraceFlag" -Tag IntegrationTests {
    BeforeAll {
        $traceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $traceSafeFlag = 3226
        $traceAbsentFlag = 2147483647
        function Test-NativeTraceFlag {
            param($Server, [int]$Flag)
            @($Server.EnumActiveGlobalTraceFlags().Rows | Where-Object TraceFlag -eq $Flag).Count -gt 0
        }
        function Set-NativeTraceFlag {
            param($Server, [int]$Flag, [bool]$Enabled)
            $operation = if ($Enabled) { "TRACEON" } else { "TRACEOFF" }
            $Server.ConnectionContext.ExecuteNonQuery("DBCC $operation ($Flag, -1) WITH NO_INFOMSGS") | Out-Null
        }
    }

    It "returns the pinned result shape and preserves requested flag order" {
        $wasEnabled = Test-NativeTraceFlag $traceServer $traceSafeFlag
        try {
            Set-NativeTraceFlag $traceServer $traceSafeFlag $true
            $warnings = @()
            $rows = @(Disable-DbaTraceFlag -SqlInstance $traceServer -TraceFlag @($traceSafeFlag, $traceAbsentFlag, $traceSafeFlag) -Confirm:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $rows.Count | Should -Be 3
            ($rows.TraceFlag -join ",") | Should -Be "$traceSafeFlag,$traceAbsentFlag,$traceSafeFlag"
            ($rows.Status -join ",") | Should -BeExactly "Successful,Skipped,Successful"
            ($rows[0].PSObject.Properties.Name -join ",") | Should -BeExactly "SourceServer,InstanceName,SqlInstance,TraceFlag,Status,Notes,DateTime"
            $rows[0].SourceServer | Should -Be $traceServer.ComputerName
            $rows[0].InstanceName | Should -Be $traceServer.ServiceName
            $rows[0].SqlInstance | Should -Be $traceServer.DomainInstanceName
            $rows[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            $rows[0].Notes | Should -BeNullOrEmpty
            $rows[1].Notes | Should -BeExactly "Trace Flag is not running."
            ($warnings -join " ") | Should -BeLike "*Trace Flag $traceAbsentFlag is not currently running on*"
            (Test-NativeTraceFlag $traceServer $traceSafeFlag) | Should -BeFalse
        } finally {
            Set-NativeTraceFlag $traceServer $traceSafeFlag $wasEnabled
        }
    }

    It "honors WhatIf and explicit false switches" -Tag "NativeChecklist:whatif-confirm", "NativeChecklist:switch-false" {
        $wasEnabled = Test-NativeTraceFlag $traceServer $traceSafeFlag
        try {
            Set-NativeTraceFlag $traceServer $traceSafeFlag $true
            @(Disable-DbaTraceFlag -SqlInstance $traceServer -TraceFlag $traceSafeFlag -WhatIf -Confirm:$false).Count | Should -Be 0
            (Test-NativeTraceFlag $traceServer $traceSafeFlag) | Should -BeTrue
            $rows = @(Disable-DbaTraceFlag -SqlInstance $traceServer -TraceFlag $traceSafeFlag -WhatIf:$false -Confirm:$false -EnableException:$false)
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -BeExactly "Successful"
            (Test-NativeTraceFlag $traceServer $traceSafeFlag) | Should -BeFalse
        } finally {
            Set-NativeTraceFlag $traceServer $traceSafeFlag $wasEnabled
        }
    }

    It "processes multiple pipeline instances and continues after a connection failure" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $savedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $listener.Start()
            $unreachable = "127.0.0.1," + $listener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $warnings = @()
            $rows = @(@($traceServer, $unreachable, $traceServer) | Disable-DbaTraceFlag -TraceFlag $traceAbsentFlag -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $rows.Count | Should -Be 2
            @($rows | Where-Object Status -ne "Skipped").Count | Should -Be 0
            ($warnings -join " ") | Should -BeLike "*Failure*"
            $prior = New-Object "System.Collections.Generic.List[object]"
            { @($traceServer, $unreachable, $traceServer) | Disable-DbaTraceFlag -TraceFlag $traceAbsentFlag -EnableException -WarningAction SilentlyContinue | ForEach-Object { $prior.Add($_) } } | Should -Throw
            $prior.Count | Should -Be 1
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $savedTimeout
            $listener.Stop()
        }
    }

    It "uses SQL authentication and fails cleanly without its credential" -Tag "NativeChecklist:sql-login" {
        $rows = @(Disable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -TraceFlag $traceAbsentFlag -EnableException -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        $rows[0].Status | Should -BeExactly "Skipped"
        $warnings = @()
        # Pin public/Disable-DbaTraceFlag.ps1:82-86 (verbatim):
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a compiled wrapper and the upstream pin predates src/:
        # no buildable commit runs the pinned function. Excerpt route: watchman 63b67fd6.
        @(Disable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -TraceFlag $traceAbsentFlag -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Failure*"
        # Pin public/Disable-DbaTraceFlag.ps1:82-86 (verbatim):
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a compiled wrapper and the upstream pin predates src/:
        # no buildable commit runs the pinned function. Excerpt route: watchman 63b67fd6.
        { Disable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -TraceFlag $traceAbsentFlag -EnableException -WarningAction SilentlyContinue } | Should -Throw
    }

    # NativeChecklist: azure-sqldb N/A -- DBCC TRACEOFF and global trace flags exist on SQL Server and Managed Instance, not Azure SQL Database: https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-traceoff-transact-sql
    It "refuses Azure SQL Database before enumerating global trace flags" {
        $azure = $null
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                break
            } catch {
                $transient = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in @(-2, 40613) -or $failure -is [System.TimeoutException] -or $failure.Message -match "timed out|timeout|wait operation") { $transient = $true }
                }
                if (-not $transient -or $attempt -eq 5) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        @(Disable-DbaTraceFlag -SqlInstance $azure -TraceFlag $traceAbsentFlag -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        { Disable-DbaTraceFlag -SqlInstance $azure -TraceFlag $traceAbsentFlag -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"
    }
}
