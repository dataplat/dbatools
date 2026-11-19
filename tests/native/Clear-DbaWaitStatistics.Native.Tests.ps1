#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Clear-DbaWaitStatistics",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Clear-DbaWaitStatistics" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeWaitServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "clears wait statistics on Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        # DBCC SQLPERF supports Azure SQL Database; execute the requested wait reset here.
        # https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-sqlperf-transact-sql
        $azureWaitServer = $null
        $azureWaitConnection = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureWaitServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureWaitServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $azureWaitConnection = $azureWaitServer.ConnectionContext
            $azureWaitOldMode = $azureWaitConnection.SqlExecutionModes
            $azureWaitConnection.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteAndCaptureSql
            $azureWaitConnection.CapturedSql.Clear()
            $azureWaitResult = @(Clear-DbaWaitStatistics -SqlInstance $azureWaitServer -Confirm:$false -EnableException)
            $azureWaitResult.Count | Should -Be 1
            $azureWaitResult[0].Status | Should -BeExactly 'Success'
            $azureWaitResult[0].SqlInstance | Should -BeExactly $azureWaitServer.DomainInstanceName
            ($azureWaitConnection.CapturedSql.Text -join ' ') | Should -Match ([regex]::Escape("DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);"))
            $azureWaitConnection.SqlExecutionModes = $azureWaitOldMode
            $azureWaitConnection.ExecuteScalar('SELECT COUNT(*) FROM sys.dm_os_wait_stats;') | Should -BeGreaterThan 0
        } finally {
            if ($azureWaitConnection) {
                $azureWaitConnection.SqlExecutionModes = $azureWaitOldMode
                $azureWaitConnection.CapturedSql.Clear()
                $azureWaitConnection.Disconnect()
            }
        }
    }

    It "returns one outcome for each pipeline record" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $splatWaitPipeline = @{
            Confirm         = $false
            WhatIf          = $false
            EnableException = $true
        }
        $nativeWaitResults = @(@($nativeWaitServer, $nativeWaitServer) | Clear-DbaWaitStatistics @splatWaitPipeline)
        $nativeWaitResults.Count | Should -Be 2
        foreach ($nativeWaitResult in $nativeWaitResults) {
            $nativeWaitResult.Status | Should -BeExactly "Success"
            $nativeWaitResult.ComputerName | Should -Not -BeNullOrEmpty
            $nativeWaitResult.InstanceName | Should -Be $nativeWaitServer.ServiceName
            $nativeWaitResult.SqlInstance | Should -Be $nativeWaitServer.DomainInstanceName
        }
    }

    It "does not execute the clear under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $nativeWaitConnection = $nativeWaitServer.ConnectionContext
        $nativeWaitOldMode = $nativeWaitConnection.SqlExecutionModes
        try {
            $nativeWaitConnection.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteAndCaptureSql
            $nativeWaitConnection.CapturedSql.Clear()
            $splatWaitWhatIf = @{
                SqlInstance     = $nativeWaitServer
                WhatIf          = $true
                Confirm         = $false
                EnableException = $true
            }
            @(Clear-DbaWaitStatistics @splatWaitWhatIf).Count | Should -Be 0
            ($nativeWaitConnection.CapturedSql.Text -join " ") | Should -Not -Match "DBCC SQLPERF"
        } finally {
            $nativeWaitConnection.SqlExecutionModes = $nativeWaitOldMode
            $nativeWaitConnection.CapturedSql.Clear()
        }
    }

    It "continues after a failed middle connection" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $splatWaitMixed = @{
            SqlInstance     = @($nativeWaitServer, "tcp:127.0.0.1,1", $nativeWaitServer)
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWaitWarnings"
        }
        $nativeWaitMixed = @(Clear-DbaWaitStatistics @splatWaitMixed)
        $nativeWaitMixed.Count | Should -Be 2
        @($nativeWaitMixed | Where-Object Status -ne "Success").Count | Should -Be 0
        ($nativeWaitWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "clears wait statistics with SQL credentials and fails cleanly without them" -Tag "NativeChecklist:sql-login" {
        $splatWaitSqlLogin = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Confirm = $false
            EnableException = $true
        }
        $nativeWaitSqlResult = @(Clear-DbaWaitStatistics @splatWaitSqlLogin)
        $nativeWaitSqlResult.Count | Should -Be 1
        $nativeWaitSqlResult[0].Status | Should -BeExactly "Success"
        $splatWaitSqlLogin.Remove("SqlCredential")
        $splatWaitSqlLogin.EnableException = $false
        $splatWaitSqlLogin.WarningAction = "SilentlyContinue"
        $splatWaitSqlLogin.WarningVariable = "nativeWaitSqlWarning"
        # No commit runs the pin: the base ships the compiled cmdlet and the pin predates buildable src/.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Clear-DbaWaitStatistics.ps1:74-78:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        @(Clear-DbaWaitStatistics @splatWaitSqlLogin).Count | Should -Be 0
        $nativeWaitSqlWarning | Should -Not -BeNullOrEmpty
        $splatWaitSqlLogin.EnableException = $true
        # No commit runs the pin: the base ships the compiled cmdlet and the pin predates buildable src/.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Clear-DbaWaitStatistics.ps1:74-78:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # Pinned private/functions/flowcontrol/Stop-Function.ps1:200-262 throws the original connection record.
        { Clear-DbaWaitStatistics @splatWaitSqlLogin } | Should -Throw
    }

    It "throws on connection failure with EnableException" -Tag "NativeChecklist:enable-exception" {
        $splatWaitFailure = @{
            SqlInstance     = "tcp:127.0.0.1,1"
            Confirm         = $false
            EnableException = $true
        }
        $nativeWaitError = $null
        try {
            $null = Clear-DbaWaitStatistics @splatWaitFailure
        } catch {
            $nativeWaitError = $_
        }
        $nativeWaitError | Should -Not -BeNullOrEmpty
        $nativeWaitError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }
}
