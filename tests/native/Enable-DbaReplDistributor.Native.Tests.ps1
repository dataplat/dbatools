#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Enable-DbaReplDistributor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Enable-DbaReplDistributor" -Tag IntegrationTests {
    BeforeAll {
        function New-NativeDistributorFixture($instance, $credential) {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential -EnableException
            $replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $server.ConnectionContext
            if ($replication.IsDistributor -or $replication.IsPublisher -or [int]$server.ConnectionContext.ExecuteScalar('SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1') -ne 0) {
                throw 'Native distributor fixture requires an instance without existing distribution or publishing; existing configuration was not changed.'
            }
            [pscustomobject]@{
                Server = $server
                Replication = $replication
                Database = 'native_distribution_' + [guid]::NewGuid().ToString('N')
            }
        }
        function Remove-NativeDistributorFixture($fixture) {
            if (-not $fixture) { return }
            $fixture.Replication.Refresh()
            $fixture.Replication.DistributionDatabases.Refresh()
            $database = $fixture.Replication.DistributionDatabases[$fixture.Database]
            if ($database) { $database.Remove() }
            $fixture.Replication.Refresh()
            if ($fixture.Replication.IsDistributor) { $fixture.Replication.UninstallDistributor($false) }
            # A partially failed install can leave this uniquely named ordinary database behind.
            $name = $fixture.Database
            if ([int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name'") -ne 0) {
                $fixture.Server.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$name]")
            }
            [int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name'") | Should -Be 0
        }
        function Assert-NativeDistributorInstalled($fixture, $output) {
            @($output).Count | Should -Be 1
            $output | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
            $output.IsDistributor | Should -BeTrue
            $output.ComputerName | Should -Not -BeNullOrEmpty
            $output.InstanceName | Should -Not -BeNullOrEmpty
            $output.SqlInstance | Should -Not -BeNullOrEmpty
            $name = $fixture.Database
            [int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name' AND is_distributor = 1") | Should -Be 1
        }
        $nativeDistributorBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
    }

    It "honors WhatIf then installs the named distribution database" -Tag "NativeChecklist:whatif-confirm", "NativeChecklist:switch-false" {
        $fixture = New-NativeDistributorFixture $TestConfig.InstanceSingle $null
        try {
            @(Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle -DistributionDatabase $fixture.Database -WhatIf -Confirm:$false -EnableException).Count | Should -Be 0
            $fixture.Replication.Refresh()
            $fixture.Replication.IsDistributor | Should -BeFalse
            $name = $fixture.Database
            [int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name'") | Should -Be 0
            $output = Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle -DistributionDatabase $fixture.Database -WhatIf:$false -Confirm:$false -EnableException
            Assert-NativeDistributorInstalled $fixture $output
        } finally { Remove-NativeDistributorFixture $fixture }
    }

    It "continues after a failed pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $fixture = New-NativeDistributorFixture $TestConfig.InstanceSingle $null
        try {
            $warnings = @()
            $output = @(@($nativeDistributorBadInstance, $TestConfig.InstanceSingle) | Enable-DbaReplDistributor -DistributionDatabase $fixture.Database -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            Assert-NativeDistributorInstalled $fixture $output
            $warnings | Should -Not -BeNullOrEmpty
        } finally { Remove-NativeDistributorFixture $fixture }
    }

    It "retains the first pipeline result when a nested connection failure terminates" -Tag "NativeChecklist:enable-exception" {
        $fixture = New-NativeDistributorFixture $TestConfig.InstanceSingle $null
        try {
            $seen = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                @($TestConfig.InstanceSingle, $nativeDistributorBadInstance) | Enable-DbaReplDistributor -DistributionDatabase $fixture.Database -Confirm:$false -EnableException | ForEach-Object { $null = $seen.Add($_) }
            } catch { $failure = $_ }
            $seen.Count | Should -Be 1
            Assert-NativeDistributorInstalled $fixture $seen[0]
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaReplServer*'
            $failure.CategoryInfo.Category | Should -Be 'ConnectionError'
        } finally { Remove-NativeDistributorFixture $fixture }
    }

    It "rejects the SQL-login instance without credentials on this leg" -Tag "NativeChecklist:sql-login" {
        $warnings = @()
        @(Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSqlLogin -WhatIf -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings | Should -Not -BeNullOrEmpty
        # Pin explicitly forwards EnableException to Get-DbaReplServer; its Connect-DbaInstance catch calls Stop-Function.
        { Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSqlLogin -WhatIf -Confirm:$false -EnableException } | Should -Throw
    }

    It "reaches the SQL-login server and reports its missing replication components" -Tag "NativeChecklist:sql-login" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        [int]$server.ConnectionContext.ExecuteScalar("SELECT IS_SRVROLEMEMBER('sysadmin')") | Should -Be 1
        [int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0
        $database = 'native_distribution_' + [guid]::NewGuid().ToString('N')
        try {
            $warnings = @()
            @(Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -DistributionDatabase $database -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join " ") | Should -BeLike "*Replication components are not installed on this server*"
            { Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -DistributionDatabase $database -Confirm:$false -EnableException } | Should -Throw "*Replication components are not installed on this server*"
            [int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$database'") | Should -Be 0
            [int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0
        } finally {
            if ([int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$database'") -ne 0) {
                $server.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$database]")
            }
        }
    }

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; distribution databases cannot be placed there: https://learn.microsoft.com/azure/azure-sql/database/replication-to-sql-database
    It "refuses Azure SQL Database before configuring a distributor" {
        $azure = $null
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $transient = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in @(-2, 40613) -or $failure.Message -match "timed out|timeout") { $transient = $true }
                }
                if (-not $transient -or $attempt -eq 5) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $database = 'native_distribution_' + [guid]::NewGuid().ToString('N')
        $warnings = @()
        @(Enable-DbaReplDistributor -SqlInstance $azure -DistributionDatabase $database -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        { Enable-DbaReplDistributor -SqlInstance $azure -DistributionDatabase $database -Confirm:$false -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
