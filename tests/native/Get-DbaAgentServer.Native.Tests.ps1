#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.
# Azure assessment: SQL Server Agent does not exist on Azure SQL Database; refuse through AzureUnsupported. https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#sql-agent-jobs

Describe "Get-DbaAgentServer native behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    It "returns the typed Agent configuration with a live calculated history flag" {
        $nativeOutput = @(Get-DbaAgentServer -SqlInstance $nativeServer -EnableException)
        $nativeOutput.Count | Should -Be 1
        $nativeAgent = $nativeOutput[0]
        $nativeAgent | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobServer
        [Object]::ReferenceEquals($nativeAgent, $nativeServer.JobServer) | Should -BeTrue
        $nativeAgent.ComputerName | Should -Not -BeNullOrEmpty
        $nativeAgent.InstanceName | Should -Not -BeNullOrEmpty
        $nativeAgent.SqlInstance | Should -Not -BeNullOrEmpty
        $nativeDisplay = $nativeAgent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        ($nativeDisplay -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,AgentDomainGroup,AgentLogLevel,AgentMailType,AgentShutdownWaitTime,ErrorLogFile,IdleCpuDuration,IdleCpuPercentage,IsCpuPollingEnabled,JobServerType,LoginTimeout,JobHistoryIsEnabled,MaximumHistoryRows,MaximumJobHistoryRows,MsxAccountCredentialName,MsxAccountName,MsxServerName,Name,NetSendRecipient,ServiceAccount,ServiceStartMode,SqlAgentAutoStart,SqlAgentMailProfile,SqlAgentRestart,SqlServerRestart,State,SysAdminOnly"
        $nativeOriginalLimit = $nativeAgent.MaximumHistoryRows
        try {
            # Change only the returned object in memory; never call Alter.
            $nativeAgent.MaximumHistoryRows = -1
            $nativeAgent.JobHistoryIsEnabled | Should -BeFalse
            $nativeAgent.MaximumHistoryRows = 1000
            $nativeAgent.JobHistoryIsEnabled | Should -BeTrue
        } finally {
            $nativeAgent.MaximumHistoryRows = $nativeOriginalLimit
        }
    }

    It "warns for a failed middle instance and continues" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeOutput = @($nativeServer, $nativeBadInstance, $nativeServer | Get-DbaAgentServer @splatNativeContinue)
        $nativeOutput.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams successful input before EnableException stops at the failed instance" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            $nativeServer, $nativeBadInstance, $nativeServer |
                Get-DbaAgentServer -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentServer Azure refusal" -Tag IntegrationTests {
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
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match "timed out|timeout|wait operation") { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureAgentServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureAgentWarnings = @()
            @(Get-DbaAgentServer -SqlInstance $azureAgentServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureAgentWarnings).Count | Should -Be 0
            ($azureAgentWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaAgentServer -SqlInstance $azureAgentServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
            $azureAgentContinued = @(Get-DbaAgentServer -SqlInstance @($azureAgentServer, $TestConfig.InstanceSingle) -EnableException:$false -WarningAction SilentlyContinue)
            $azureAgentContinued.Count | Should -BeGreaterThan 0
            $azureAgentContinued[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobServer
        } finally {
            if ($azureAgentServer) { $azureAgentServer.ConnectionContext.Disconnect() }
        }
    }
}

Describe "Get-DbaAgentServer SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    It "returns the Agent configuration with SQL credentials" {
        $splatLoginServer = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginAgentOutput = @(Get-DbaAgentServer @splatLoginServer)
        $loginAgentOutput.Count | Should -Be 1
        $loginAgentOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobServer
        $loginAgentOutput[0].SqlInstance | Should -BeExactly $loginAgentOutput[0].Parent.DomainInstanceName
        $loginAgentOutput[0].JobHistoryIsEnabled | Should -Be ($loginAgentOutput[0].MaximumHistoryRows -ne -1)
    }

    It "warns without output when SQL credentials are omitted" {
        $loginAgentWarnings = @()
        $splatLoginAgentDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginAgentWarnings"
        }
        # Pin public/Get-DbaAgentServer.ps1:118-122, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        @(Get-DbaAgentServer @splatLoginAgentDenied).Count | Should -Be 0
        $loginAgentWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # The pinned function catches its Connect-DbaInstance failure and invokes Stop-Function directly.
        # Pin public/Get-DbaAgentServer.ps1:118-122, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        { Get-DbaAgentServer -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw
    }
}
