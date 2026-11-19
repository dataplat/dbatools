#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and closes caller-owned connection objects rather than authenticating.
# NativeChecklist: multi-instance-failure N/A -- no instances are connected; failure between caller-owned connection objects is tested with pipeline-multiple.
param(
    $ModuleName = "dbatools",
    $CommandName = "Disconnect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Disconnect-DbaInstance" -Tag IntegrationTests {
    BeforeAll {
        if (-not ('NativeDisconnectFailureContext' -as [type])) {
            Add-Type -TypeDefinition 'public class NativeDisconnectFailureContext { public string ConnectionString = "Data Source=probe"; public void Disconnect() { throw new System.InvalidOperationException("probe .NET disconnect failure"); } }'
        }
        $nativeDisconnectConnections = New-Object System.Collections.ArrayList
        function New-NativeDisconnectConnection {
            param([string]$Instance = $TestConfig.InstanceSingle, [switch]$LegacyProvider)
            if ($LegacyProvider) {
                $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
            } else {
                $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
            }
            $builder['Data Source'] = $Instance
            $builder['Integrated Security'] = $true
            $builder['Pooling'] = $false
            $builder['Encrypt'] = $false
            $builder['TrustServerCertificate'] = $true
            $builder['Connect Timeout'] = 15
            $builder['Application Name'] = 'native-disconnect-' + [guid]::NewGuid().ToString('N')
            if ($LegacyProvider) {
                $connection = New-Object System.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
            } else {
                $connection = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
            }
            $null = $nativeDisconnectConnections.Add($connection)
            $connection.Open()
            $connection
        }
    }

    AfterAll {
        foreach ($connection in $nativeDisconnectConnections) { $connection.Dispose() }
    }

    It "honors WhatIf and closes both SqlClient providers with WhatIf false" -Tag "NativeChecklist:whatif-confirm", "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
        $modern = New-NativeDisconnectConnection
        $legacy = New-NativeDisconnectConnection -LegacyProvider
        @(@($modern, $legacy) | Disconnect-DbaInstance -WhatIf -Confirm:$false -EnableException).Count | Should -Be 0
        $modern.State | Should -Be Open
        $legacy.State | Should -Be Open
        $result = @(@($modern, $legacy) | Disconnect-DbaInstance -WhatIf:$false -Confirm:$false -EnableException)
        $result.Count | Should -Be 2
        $result[0].ConnectionType | Should -BeExactly 'Microsoft.Data.SqlClient.SqlConnection'
        $result[1].ConnectionType | Should -BeExactly 'System.Data.SqlClient.SqlConnection'
        foreach ($row in $result) { $row.State | Should -Be Closed }
        $modern.State | Should -Be Closed
        $legacy.State | Should -Be Closed
    }

    It "disconnects an SMO server and removes its active cache entry" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName ('native-disconnect-smo-' + [guid]::NewGuid().ToString('N')) -EnableException
        try {
            $server.ConnectionContext.Connect()
            $key = $server.ConnectionContext.ConnectionString
            [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.ContainsKey($key) | Should -BeTrue
            $result = @($server | Disconnect-DbaInstance -Confirm:$false -EnableException)
            $result.Count | Should -Be 1
            $result[0].State | Should -BeExactly 'Disconnected'
            $result[0].SqlInstance | Should -Be $server.Name
            $result[0].ConnectionType | Should -BeExactly 'Microsoft.SqlServer.Management.Smo.Server'
            $server.ConnectionContext.SqlConnectionObject.State | Should -Be Closed
            [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.ContainsKey($key) | Should -BeFalse
        } finally { $server.ConnectionContext.Disconnect() }
    }

    It "continues after a bad connection object and captures its silent error once" -Tag "NativeChecklist:enable-exception", "NativeChecklist:pipeline-multiple" {
        $first = New-NativeDisconnectConnection
        $last = New-NativeDisconnectConnection
        $bad = [pscustomobject]@{ Name = 'native-disconnect-bad'; ConnectionContext = [pscustomobject]@{ ConnectionString = 'native-disconnect-bad' } }
        $disconnectWarnings = @()
        $disconnectErrors = @()
        $result = @(@($first, $bad, $last) | Disconnect-DbaInstance -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable disconnectWarnings -ErrorVariable disconnectErrors)
        $result.Count | Should -Be 2
        $first.State | Should -Be Closed
        $last.State | Should -Be Closed
        $disconnectWarnings.Count | Should -Be 1
        ($disconnectWarnings -join ' ') | Should -BeLike '*Failed to disconnect*'
        $disconnectErrors.Count | Should -Be 1
        $disconnectErrors[0].TargetObject | Should -BeNullOrEmpty
        $firstCapturedError = $disconnectErrors[0]
        $null = Disconnect-DbaInstance -InputObject $bad -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -ErrorVariable +disconnectErrors
        $disconnectErrors.Count | Should -Be 2
        [object]::ReferenceEquals($disconnectErrors[0], $firstCapturedError) | Should -BeTrue
    }

    It "captures the pinned CLR failure payload without displaying an error stream" -Tag "NativeChecklist:enable-exception" {
        $failureObject = [pscustomobject]@{ Name = 'probe'; ConnectionContext = (New-Object NativeDisconnectFailureContext) }
        $capturedFailure = @()
        $merged = @(Disconnect-DbaInstance -InputObject $failureObject -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable capturedFailure 2>&1)
        $merged.Count | Should -Be 0
        $capturedFailure.Count | Should -Be 1
        $capturedFailure[0].FullyQualifiedErrorId | Should -BeExactly 'dbatools_Disconnect-DbaInstance'
        $capturedFailure[0].Exception.Message | Should -BeExactly 'probe .NET disconnect failure'
        $capturedFailure[0].CategoryInfo.Category | Should -Be 'NotSpecified'
        $capturedFailure[0].TargetObject | Should -BeNullOrEmpty
        $capturedFailure[0].Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        $capturedFailure[0].Exception.InnerException.InnerException | Should -BeOfType System.InvalidOperationException
        $capturedFailure[0].Exception.InnerException.InnerException.Message | Should -BeExactly 'probe .NET disconnect failure'
    }

    It "retains earlier output and leaves later connections open when EnableException terminates" -Tag "NativeChecklist:enable-exception" {
        $first = New-NativeDisconnectConnection
        $last = New-NativeDisconnectConnection
        $bad = [pscustomobject]@{ Name = 'native-disconnect-bad'; ConnectionContext = [pscustomobject]@{ ConnectionString = 'native-disconnect-bad' } }
        $seen = New-Object System.Collections.ArrayList
        $failure = $null
        try {
            @($first, $bad, $last) | Disconnect-DbaInstance -Confirm:$false -EnableException | ForEach-Object { $null = $seen.Add($_) }
        } catch { $failure = $_ }
        $seen.Count | Should -Be 1
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Disconnect-DbaInstance*'
        $first.State | Should -Be Closed
        $last.State | Should -Be Open
    }

    It "closes a caller connection to SQL Server 2005" -Tag "NativeChecklist:sql2005" {
        $connection = New-NativeDisconnectConnection -Instance $TestConfig.InstanceLegacy
        $query = $connection.CreateCommand()
        try {
            $query.CommandText = "SELECT CONVERT(varchar(40), SERVERPROPERTY('ProductVersion'));"
            $query.ExecuteScalar() | Should -Match '^9\.'
        } finally { $query.Dispose() }
        $result = @($connection | Disconnect-DbaInstance -Confirm:$false -EnableException)
        $result.Count | Should -Be 1
        $result[0].State | Should -Be Closed
        $connection.State | Should -Be Closed
    }

    It "closes a caller connection to Azure SQL Database and masks its password" -Tag "NativeChecklist:azure-sqldb" {
        $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        $builder['Data Source'] = $TestConfig.AzureSqlDbServer
        $builder['Initial Catalog'] = $TestConfig.AzureSqlDbName
        $builder['User ID'] = $TestConfig.AzureSqlDbCred.UserName
        $builder['Password'] = $TestConfig.AzureSqlDbCred.GetNetworkCredential().Password
        $builder['Encrypt'] = $true
        $builder['TrustServerCertificate'] = $false
        $builder['Persist Security Info'] = $true
        $builder['Pooling'] = $false
        $builder['Connect Timeout'] = 15
        $connection = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
        $null = $nativeDisconnectConnections.Add($connection)
        for ($attempt = 1; $attempt -le 7; $attempt++) {
            try { $connection.Open(); break } catch {
                $retryable = $false
                $connectionError = $_.Exception
                while ($connectionError) {
                    if ($connectionError.Number -in @(-2, 40613) -or $connectionError -is [System.TimeoutException]) { $retryable = $true }
                    $connectionError = $connectionError.InnerException
                }
                if (-not $retryable -or $attempt -eq 7) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $query = $connection.CreateCommand()
        try {
            $query.CommandText = "SELECT CONVERT(int, SERVERPROPERTY('EngineEdition'));"
            $query.ExecuteScalar() | Should -Be 5
        } finally { $query.Dispose() }
        $result = @($connection | Disconnect-DbaInstance -Confirm:$false -EnableException)
        $result.Count | Should -Be 1
        $result[0].State | Should -Be Closed
        $result[0].ConnectionString.Contains($builder.Password) | Should -BeFalse
        $connection.State | Should -Be Closed
    }
}
