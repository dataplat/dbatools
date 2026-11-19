#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.

Describe "Get-DbaAgentLog native behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    It "preserves DataRow output, log-number repetition, and the optional instance parameter" {
        $nativeOutput = @(Get-DbaAgentLog -SqlInstance $nativeServer -LogNumber 0 -EnableException)
        $nativeOutput.Count | Should -BeGreaterThan 0
        $nativeOutput[0] | Should -BeOfType System.Data.DataRow
        $nativeOutput[0].LogDate | Should -BeOfType DateTime
        $nativeOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        $nativeOutput[0].InstanceName | Should -Not -BeNullOrEmpty
        $nativeOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        ($nativeOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,LogDate,ProcessInfo,Text"
        $nativeRepeated = @(Get-DbaAgentLog -SqlInstance $nativeServer -LogNumber 0, 0 -EnableException)
        $nativeRepeated.Count | Should -BeGreaterOrEqual ($nativeOutput.Count * 2)
        @(Get-DbaAgentLog).Count | Should -Be 0
    }

    It "stops quietly when downstream selects only the first row" {
        foreach ($nativeStopEnableException in @($false, $true)) {
            $nativeEarlyWarnings = @()
            $nativeEarlyErrors = @()
            $splatNativeEarly = @{
                SqlInstance     = @($nativeServer, $nativeBadInstance)
                LogNumber       = @(0, 0)
                EnableException = $nativeStopEnableException
                WarningVariable = "nativeEarlyWarnings"
                ErrorVariable   = "nativeEarlyErrors"
                ErrorAction     = "Stop"
            }
            $nativeFirstRow = @(Get-DbaAgentLog @splatNativeEarly | Select-Object -First 1)
            $nativeFirstRow.Count | Should -Be 1
            $nativeEarlyWarnings | Should -BeNullOrEmpty
            $nativeEarlyErrors | Should -BeNullOrEmpty
        }
    }

    It "warns for a failed middle instance and continues" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeInitialCount = @(Get-DbaAgentLog -SqlInstance $nativeServer -EnableException).Count
        $nativeOutput = @($nativeServer, $nativeBadInstance, $nativeServer | Get-DbaAgentLog @splatNativeContinue)
        $nativeOutput.Count | Should -BeGreaterOrEqual ($nativeInitialCount * 2)
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams successful input before EnableException stops at the failed instance" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            $nativeServer, $nativeBadInstance, $nativeServer |
                Get-DbaAgentLog -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -BeGreaterThan 0
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentLog Azure refusal" -Tag IntegrationTests {
    It "refuses Azure SQL Database and continues to the next instance" -Tag NativeChecklist:azure-sqldb {
        $azureAgentServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureAgentServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match 'timed out|timeout|wait operation') { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureAgentServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureAgentWarnings = @()
            @(Get-DbaAgentLog -SqlInstance $azureAgentServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureAgentWarnings).Count | Should -Be 0
            ($azureAgentWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaAgentLog -SqlInstance $azureAgentServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
            $azureAgentContinued = @(Get-DbaAgentLog -SqlInstance @($azureAgentServer, $TestConfig.InstanceSingle) -EnableException:$false -WarningAction SilentlyContinue)
            $azureAgentContinued.Count | Should -BeGreaterThan 0
            $azureAgentContinued[0] | Should -BeOfType System.Data.DataRow
        } finally {
            if ($azureAgentServer) { $azureAgentServer.ConnectionContext.Disconnect() }
        }
    }
}

Describe "Get-DbaAgentLog SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginLogServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
    }

    It "reads the current Agent log with SQL credentials" {
        $splatLoginLog = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            LogNumber = 0
            EnableException = $true
        }
        $loginLogOutput = @(Get-DbaAgentLog @splatLoginLog)
        $loginLogOutput.Count | Should -BeGreaterThan 0
        $loginLogOutput[0] | Should -BeOfType System.Data.DataRow
        $loginLogOutput[0].LogDate | Should -BeOfType DateTime
        $loginLogOutput[0].Text | Should -Not -BeNullOrEmpty
        $loginLogOutput[0].SqlInstance | Should -BeExactly $loginLogServer.DomainInstanceName
    }

    It "warns without output when SQL credentials are omitted" {
        $loginLogWarnings = @()
        $splatLoginLogDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            LogNumber = 0
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "loginLogWarnings"
        }
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentLog.ps1:85-90
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Watchman 49f13ebb permits this exact pinned connection path for this recheck:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        @(Get-DbaAgentLog @splatLoginLogDenied).Count | Should -Be 0
        $loginLogWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentLog.ps1:85-90
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Watchman 49f13ebb permits this exact pinned connection path for this recheck:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        { Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSqlLogin -LogNumber 0 -EnableException } | Should -Throw
    }
}
