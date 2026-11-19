#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- TLS certificate read only; no ShouldProcess in the pin.
# NativeChecklist: sql-login N/A -- TLS pre-login handshake does not authenticate to SQL Server; the pin has no SqlCredential.

Describe 'Native Get-DbaNetworkEncryption real TLS' -Tag IntegrationTests {
    BeforeAll {
        $instance = [DbaInstanceParameter]$TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance
        $port = $server.ConnectionContext.ExecuteScalar("SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID")
        if ($null -eq $port -or $port -is [DBNull]) {
            $server = Connect-DbaInstance -SqlInstance ('tcp:' + $instance.SqlFullName)
            $port = $server.ConnectionContext.ExecuteScalar("SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID")
        }
        $port | Should -BeGreaterThan 0
        $endpoint = $instance.ComputerName + ',' + $port
        $module = Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1
        $expected = & $module { param($computer, $port) Get-SqlServerTlsCertificate -ComputerName $computer -ConnectionType TCP -Port $port -ErrorAction Stop -WarningAction SilentlyContinue } $instance.ComputerName $port
        $expected.Thumbprint | Should -Not -BeNullOrEmpty
    }
    It 'reads the same real server certificate through SQL Browser and an explicit TCP port' {
        foreach ($address in @($instance, $endpoint)) {
            $rows = @(Get-DbaNetworkEncryption -SqlInstance $address -EnableException -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 1
            foreach ($name in 'Subject', 'Issuer', 'Thumbprint', 'NotBefore', 'SerialNumber') { $rows[0].$name | Should -Be $expected.$name }
            $rows[0].Expires | Should -Be $expected.NotAfter
            $rows[0].Certificate | Should -BeOfType System.Security.Cryptography.X509Certificates.X509Certificate2
            [Convert]::ToBase64String($rows[0].Certificate.RawData) | Should -BeExactly ([Convert]::ToBase64String($expected.RawData))
            @($rows[0].DnsNameList.Unicode) | Should -BeExactly @($expected.DnsNameList.Unicode)
        }
    }
    It 'supports arrays and pipeline input with EnableException false' -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $rows = @($endpoint, $endpoint | Get-DbaNetworkEncryption -EnableException:$false -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 2
        @($rows | Where-Object Thumbprint -ne $expected.Thumbprint).Count | Should -Be 0
        @(Get-DbaNetworkEncryption -SqlInstance $endpoint, $endpoint -EnableException:$false -WarningAction SilentlyContinue).Count | Should -Be 2
    }
    It "accepts the SQL Server instance as the first positional argument" {
        $rows = @(Get-DbaNetworkEncryption $endpoint -EnableException -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        [Convert]::ToBase64String($rows[0].Certificate.RawData) | Should -BeExactly ([Convert]::ToBase64String($expected.RawData))
    }
    It 'continues after a refused endpoint and stops with EnableException' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $bad = $instance.ComputerName + ',1'
        $rows = @(Get-DbaNetworkEncryption -SqlInstance $bad, $endpoint -WarningAction SilentlyContinue -WarningVariable warnings)
        $rows.Count | Should -Be 1
        $rows[0].Thumbprint | Should -Be $expected.Thumbprint
        "$warnings" | Should -BeLike '*Failed to retrieve TLS certificate*'
        { Get-DbaNetworkEncryption -SqlInstance $bad, $endpoint -EnableException -WarningAction SilentlyContinue } | Should -Throw -ErrorId 'dbatools_Get-DbaNetworkEncryption*'
    }
    It 'retrieves the Azure SQL Database TLS certificate without SQL authentication' -Tag NativeChecklist:azure-sqldb {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        $azureServer = $null
        # Resume only the setup connection; the certificate command below runs once without credentials.
        for ($azureAttempt = 0; $azureAttempt -le 6; $azureAttempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                $azureFailure = $PSItem.Exception
                $azureResuming = $false
                while ($azureFailure) {
                    if ($azureFailure.Number -in 40613, -2 -or $azureFailure.NativeErrorCode -eq 258 -or $azureFailure.Message -match "timeout|timed out") {
                        $azureResuming = $true
                    }
                    $azureFailure = $azureFailure.InnerException
                }
                if (-not $azureResuming -or $azureAttempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $rows = @(Get-DbaNetworkEncryption -SqlInstance ($TestConfig.AzureSqlDbServer + ',1433') -EnableException -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        $rows[0].Thumbprint | Should -Not -BeNullOrEmpty
        $rows[0].Certificate | Should -BeOfType System.Security.Cryptography.X509Certificates.X509Certificate2
        $rows[0].Expires | Should -BeGreaterThan (Get-Date)
        $rows[0].Issuer | Should -Not -BeNullOrEmpty
    }
}
