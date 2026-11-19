#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMail",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.
# Database Mail is unavailable on Azure SQL Database: https://learn.microsoft.com/sql/relational-databases/database-mail/database-mail

Describe "Get-DbaDbMail native behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    It "returns the typed mail configuration with its original collections and display" {
        $nativeOutput = @(Get-DbaDbMail -SqlInstance $nativeServer -EnableException)
        $nativeOutput.Count | Should -Be 1
        $nativeMail = $nativeOutput[0]
        $nativeMail | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.SqlMail
        [Object]::ReferenceEquals($nativeMail, $nativeServer.Mail) | Should -BeTrue
        $nativeMail.ComputerName | Should -Not -BeNullOrEmpty
        $nativeMail.InstanceName | Should -Not -BeNullOrEmpty
        $nativeMail.SqlInstance | Should -Not -BeNullOrEmpty
        @($nativeMail.ConfigurationValues).Count | Should -BeGreaterThan 0
        ($nativeMail.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Profiles,Accounts,ConfigurationValues,Properties"
    }

    It "stops quietly when downstream selects only the first configuration" {
        foreach ($nativeStopEnableException in @($false, $true)) {
            $nativeEarlyWarnings = @()
            $nativeEarlyErrors = @()
            $splatNativeEarly = @{
                SqlInstance     = @($nativeServer, $nativeBadInstance)
                EnableException = $nativeStopEnableException
                WarningVariable = "nativeEarlyWarnings"
                ErrorVariable   = "nativeEarlyErrors"
                ErrorAction     = "Stop"
            }
            $nativeFirstMail = @(Get-DbaDbMail @splatNativeEarly | Select-Object -First 1)
            $nativeFirstMail.Count | Should -Be 1
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
        $nativeOutput = @($nativeServer, $nativeBadInstance, $nativeServer | Get-DbaDbMail @splatNativeContinue)
        $nativeOutput.Count | Should -Be 2
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "streams successful input before EnableException stops at the failed instance" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            $nativeServer, $nativeBadInstance, $nativeServer |
                Get-DbaDbMail -EnableException |
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

Describe "Get-DbaDbMail SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    It "returns Database Mail configuration with SQL credentials" {
        $splatLoginMail = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginMailOutput = @(Get-DbaDbMail @splatLoginMail)
        $loginMailOutput.Count | Should -Be 1
        $loginMailOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.SqlMail
        $loginMailOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        @($loginMailOutput[0].ConfigurationValues).Count | Should -BeGreaterThan 0
    }

    It "warns without output when SQL credentials are omitted" {
        $loginMailWarnings = @()
        $splatLoginMailDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginMailWarnings"
        }
        # Pin public/Get-DbaDbMail.ps1:78-82, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        @(Get-DbaDbMail @splatLoginMailDenied).Count | Should -Be 0
        $loginMailWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # The pinned function catches its Connect-DbaInstance failure and invokes Stop-Function directly.
        # Pin public/Get-DbaDbMail.ps1:78-82, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        { Get-DbaDbMail -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw
    }
}

Describe "Get-DbaDbMail Azure SQL Database" -Tag IntegrationTests {
    It "refuses Azure SQL Database before reading Database Mail" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $resuming = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in 40613, -2 -or $failure -is [System.TimeoutException] -or $failure.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Get-DbaDbMail -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Get-DbaDbMail -SqlInstance $azure -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { $azure.ConnectionContext.Disconnect() }
    }
}
