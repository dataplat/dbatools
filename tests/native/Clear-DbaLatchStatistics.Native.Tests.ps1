#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Clear-DbaLatchStatistics",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Clear-DbaLatchStatistics" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeLatchServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "clears latch statistics on Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        # DBCC SQLPERF supports Azure SQL Database; manager probe 4b0ad6832ec8 confirmed this lab operation.
        # https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-sqlperf-transact-sql
        $azureLatchServer = $null
        $azureLatchConnection = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureLatchServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
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
            $azureLatchServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $azureLatchConnection = $azureLatchServer.ConnectionContext
            $azureLatchOldMode = $azureLatchConnection.SqlExecutionModes
            $azureLatchConnection.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteAndCaptureSql
            $azureLatchConnection.CapturedSql.Clear()
            $azureLatchResult = @(Clear-DbaLatchStatistics -SqlInstance $azureLatchServer -Confirm:$false -EnableException)
            $azureLatchResult.Count | Should -Be 1
            $azureLatchResult[0].Status | Should -BeExactly 'Success'
            $azureLatchResult[0].SqlInstance | Should -BeExactly $azureLatchServer.DomainInstanceName
            ($azureLatchConnection.CapturedSql.Text -join ' ') | Should -Match ([regex]::Escape("DBCC SQLPERF (N'sys.dm_os_latch_stats', CLEAR);"))
            $azureLatchConnection.SqlExecutionModes = $azureLatchOldMode
            $azureLatchConnection.ExecuteScalar('SELECT COUNT(*) FROM sys.dm_os_latch_stats;') | Should -BeGreaterThan 0
        } finally {
            if ($azureLatchConnection) {
                $azureLatchConnection.SqlExecutionModes = $azureLatchOldMode
                $azureLatchConnection.CapturedSql.Clear()
                $azureLatchConnection.Disconnect()
            }
        }
    }

    It "returns one outcome for each pipeline record" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $splatLatchPipeline = @{
            Confirm         = $false
            WhatIf          = $false
            EnableException = $true
        }
        $nativeLatchResults = @(@($nativeLatchServer, $nativeLatchServer) | Clear-DbaLatchStatistics @splatLatchPipeline)
        $nativeLatchResults.Count | Should -Be 2
        foreach ($nativeLatchResult in $nativeLatchResults) {
            $nativeLatchResult.Status | Should -BeExactly "Success"
            $nativeLatchResult.ComputerName | Should -Not -BeNullOrEmpty
            $nativeLatchResult.InstanceName | Should -Be $nativeLatchServer.ServiceName
            $nativeLatchResult.SqlInstance | Should -Be $nativeLatchServer.DomainInstanceName
        }
    }

    It "does not execute the clear under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $nativeLatchConnection = $nativeLatchServer.ConnectionContext
        $nativeLatchOldMode = $nativeLatchConnection.SqlExecutionModes
        try {
            $nativeLatchConnection.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteAndCaptureSql
            $nativeLatchConnection.CapturedSql.Clear()
            $splatLatchWhatIf = @{
                SqlInstance     = $nativeLatchServer
                WhatIf          = $true
                Confirm         = $false
                EnableException = $true
            }
            @(Clear-DbaLatchStatistics @splatLatchWhatIf).Count | Should -Be 0
            ($nativeLatchConnection.CapturedSql.Text -join " ") | Should -Not -Match "DBCC SQLPERF"
        } finally {
            $nativeLatchConnection.SqlExecutionModes = $nativeLatchOldMode
            $nativeLatchConnection.CapturedSql.Clear()
        }
    }

    It "continues after a failed middle connection" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $splatLatchMixed = @{
            SqlInstance     = @($nativeLatchServer, "tcp:127.0.0.1,1", $nativeLatchServer)
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeLatchWarnings"
        }
        $nativeLatchMixed = @(Clear-DbaLatchStatistics @splatLatchMixed)
        $nativeLatchMixed.Count | Should -Be 2
        @($nativeLatchMixed | Where-Object Status -ne "Success").Count | Should -Be 0
        ($nativeLatchWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "clears latch statistics with SQL credentials and fails cleanly without them" -Tag "NativeChecklist:sql-login" {
        $splatLatchSqlLogin = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Confirm = $false
            EnableException = $true
        }
        $nativeLatchSqlResult = @(Clear-DbaLatchStatistics @splatLatchSqlLogin)
        $nativeLatchSqlResult.Count | Should -Be 1
        $nativeLatchSqlResult[0].Status | Should -BeExactly "Success"
        $splatLatchSqlLogin.Remove("SqlCredential")
        $splatLatchSqlLogin.EnableException = $false
        $splatLatchSqlLogin.WarningAction = "SilentlyContinue"
        $splatLatchSqlLogin.WarningVariable = "nativeLatchSqlWarning"
        # No commit runs the pin: the base ships the compiled cmdlet and the pin predates buildable src/.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Clear-DbaLatchStatistics.ps1:87-91:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        @(Clear-DbaLatchStatistics @splatLatchSqlLogin).Count | Should -Be 0
        $nativeLatchSqlWarning | Should -Not -BeNullOrEmpty
        $splatLatchSqlLogin.EnableException = $true
        # No commit runs the pin: the base ships the compiled cmdlet and the pin predates buildable src/.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Clear-DbaLatchStatistics.ps1:87-91:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # Pinned private/functions/flowcontrol/Stop-Function.ps1:200-262 throws the original connection record.
        { Clear-DbaLatchStatistics @splatLatchSqlLogin } | Should -Throw
    }

    It "throws on connection failure with EnableException" -Tag "NativeChecklist:enable-exception" {
        $splatLatchFailure = @{
            SqlInstance     = "tcp:127.0.0.1,1"
            Confirm         = $false
            EnableException = $true
        }
        $nativeLatchError = $null
        try {
            $null = Clear-DbaLatchStatistics @splatLatchFailure
        } catch {
            $nativeLatchError = $_
        }
        $nativeLatchError | Should -Not -BeNullOrEmpty
        $nativeLatchError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }
}
