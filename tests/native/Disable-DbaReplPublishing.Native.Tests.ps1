#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaReplPublishing",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Disable-DbaReplPublishing" -Tag IntegrationTests {
    BeforeAll {
        # Makes the instance its own distributor and local publisher through RMO, as Microsoft Learn's
        # DistributionPublisher example does. It refuses an instance that already has replication configured.
        function New-NativePublisherFixture($instance) {
            $server = Connect-DbaInstance -SqlInstance $instance -EnableException
            $replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $server.ConnectionContext
            if ($replication.IsDistributor -or $replication.IsPublisher -or [int]$server.ConnectionContext.ExecuteScalar('SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1') -ne 0) {
                throw 'Native publisher fixture requires an instance without existing distribution or publishing; existing configuration was not changed.'
            }
            $fixture = [pscustomobject]@{
                Instance      = $instance
                Server        = $server
                Replication   = $replication
                Database      = 'native_distribution_' + [guid]::NewGuid().ToString('N')
                PublisherName = [string]$server.ConnectionContext.ExecuteScalar('SELECT @@SERVERNAME')
            }
            try {
                $distributionDatabase = New-Object Microsoft.SqlServer.Replication.DistributionDatabase -ArgumentList $fixture.Database, $server.ConnectionContext
                $replication.InstallDistributor([string]$null, $distributionDatabase)
                $publisher = New-Object Microsoft.SqlServer.Replication.DistributionPublisher -ArgumentList $fixture.PublisherName, $server.ConnectionContext
                $publisher.DistributionDatabase = $fixture.Database
                # A path on the server: Join-Path would resolve its drive on the test host instead.
                $publisher.WorkingDirectory = $server.InstallDataDirectory.TrimEnd('\') + '\ReplData'
                $publisher.PublisherSecurity.WindowsAuthentication = $true
                $publisher.Create()
                $replication.Refresh()
                $replication.IsPublisher | Should -BeTrue
            } catch {
                # A half-built fixture is removed before the failure is reported, so later tests start clean.
                Remove-NativePublisherFixture $fixture
                throw
            }
            $fixture
        }
        function Get-NativePublisherCount($fixture) {
            [int]$fixture.Server.ConnectionContext.ExecuteScalar('SELECT COUNT(*) FROM msdb.dbo.MSdistpublishers')
        }
        function Remove-NativePublisherFixture($fixture) {
            if (-not $fixture) { return }
            # A fresh connection, so cleanup never depends on the state the command left its own connection in.
            $fixture.Server = Connect-DbaInstance -SqlInstance $fixture.Instance -EnableException
            $fixture.Replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $fixture.Server.ConnectionContext
            $fixture.Replication.Refresh()
            $fixture.Replication.DistributionPublishers.Refresh()
            foreach ($publisher in @($fixture.Replication.DistributionPublishers)) { $publisher.Remove($true) }
            $fixture.Replication.DistributionDatabases.Refresh()
            $database = $fixture.Replication.DistributionDatabases[$fixture.Database]
            if ($database) { $database.Remove() }
            $fixture.Replication.Refresh()
            if ($fixture.Replication.IsDistributor) { $fixture.Replication.UninstallDistributor($false) }
            $name = $fixture.Database
            if ([int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name'") -ne 0) {
                $fixture.Server.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$name]")
            }
            [int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0
        }
        $nativePublishingBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
    }

    It "honors WhatIf, then removes the local publisher without Force" -Tag "NativeChecklist:whatif-confirm", "NativeChecklist:switch-false" {
        $fixture = New-NativePublisherFixture $TestConfig.InstanceSingle
        try {
            # The pin refreshes and returns the server even when ShouldProcess declines.
            $preview = @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -WhatIf -Confirm:$false -EnableException)
            $preview.Count | Should -Be 1
            $preview[0].IsPublisher | Should -BeTrue
            Get-NativePublisherCount $fixture | Should -Be 1

            $output = @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Force:$false -WhatIf:$false -Confirm:$false -EnableException)
            $output.Count | Should -Be 1
            $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.ReplicationServer
            $output[0].IsPublisher | Should -BeFalse
            $output[0].ComputerName | Should -Not -BeNullOrEmpty
            $output[0].InstanceName | Should -Not -BeNullOrEmpty
            $output[0].SqlInstance | Should -Not -BeNullOrEmpty
            Get-NativePublisherCount $fixture | Should -Be 0
        } finally { Remove-NativePublisherFixture $fixture }
    }

    It "removes only the instance's own publisher registration at its distributor" {
        $fixture = New-NativePublisherFixture $TestConfig.InstanceSingle
        $other = 'NATIVE-PUB2-' + [guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        try {
            # Both names are generated here (hex and a fixed prefix), so they are safe as literals.
            $null = $fixture.Server.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_adddistpublisher @publisher = N'$other', @distribution_db = N'$($fixture.Database)', @security_mode = 1")
            Get-NativePublisherCount $fixture | Should -Be 2

            $output = @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Force -Confirm:$false -EnableException)
            $output.Count | Should -Be 1
            $output[0].IsPublisher | Should -BeFalse
            $left = @($fixture.Server.ConnectionContext.ExecuteWithResults('SELECT name FROM msdb.dbo.MSdistpublishers').Tables[0].Rows | ForEach-Object { $PSItem.name })
            $left.Count | Should -Be 1
            $left[0] | Should -BeExactly $other
        } finally { Remove-NativePublisherFixture $fixture }
    }

    It "continues after a failed pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $fixture = New-NativePublisherFixture $TestConfig.InstanceSingle
        try {
            $warnings = @()
            $output = @(@($nativePublishingBadInstance, $TestConfig.InstanceSingle) | Disable-DbaReplPublishing -Force -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $output.Count | Should -Be 1
            $output[0].IsPublisher | Should -BeFalse
            Get-NativePublisherCount $fixture | Should -Be 0
            ($warnings -join ' ') | Should -BeLike '*Error connecting to*'
            ($warnings -join ' ') | Should -Not -BeLike '*enabled for publishing*'
        } finally { Remove-NativePublisherFixture $fixture }
    }

    It "stops at a connection failure with EnableException" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        try {
            $null = Disable-DbaReplPublishing -SqlInstance $nativePublishingBadInstance -Confirm:$false -EnableException
        } catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaReplServer*'
        $failure.CategoryInfo.Category | Should -Be 'ConnectionError'
    }

    It "warns for a non-publisher with EnableException false and throws with it" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        (Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle).IsPublisher | Should -BeFalse
        $warnings = @()
        @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join ' ') | Should -BeLike "*isn't currently enabled for publishing*"
        $failure = $null
        try {
            $null = Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -EnableException
        } catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Disable-DbaReplPublishing*'
        $failure.CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }

    It "authenticates with SQL credentials and reports the server is not a publisher" -Tag "NativeChecklist:sql-login" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        [int]$server.ConnectionContext.ExecuteScalar("SELECT IS_SRVROLEMEMBER('sysadmin')") | Should -Be 1
        [int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0
        $warnings = @()
        @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join ' ') | Should -BeLike "*isn't currently enabled for publishing*"
        ($warnings -join ' ') | Should -Not -BeLike '*Error connecting to*'
        { Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Confirm:$false -EnableException } | Should -Throw "*isn't currently enabled for publishing*"
    }

    It "rejects the SQL-login instance without credentials" -Tag "NativeChecklist:sql-login" {
        # Pin public/Disable-DbaReplPublishing.ps1:93, verbatim:
        # $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
        # Pin public/Get-DbaReplServer.ps1:89-90 and 98-99, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # Pin public/Connect-DbaInstance.ps1:499-503 and 1501-1502, verbatim:
        # if ($DisableException) {
        #     $EnableException = $false
        # } else {
        #     $EnableException = $true
        # }
        # if (-not $connectionSucceeded) {
        #     Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
        # Stop-Function names a Connect-*Instance target "Error connecting to [<instance>]" in the record it writes and throws.
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt; manager 26cdfe6de457.
        $warnings = @()
        @(Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSqlLogin -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join ' ') | Should -BeLike '*Error connecting to*'
        # The pin forwards EnableException to Get-DbaReplServer, whose catch calls Stop-Function.
        { Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSqlLogin -Confirm:$false -EnableException } | Should -Throw
    }

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; it cannot be a publisher or distributor: https://learn.microsoft.com/azure/azure-sql/database/replication-to-sql-database
    It "refuses Azure SQL Database before disabling publishing" {
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
        $warnings = @()
        @(Disable-DbaReplPublishing -SqlInstance $azure -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        { Disable-DbaReplPublishing -SqlInstance $azure -Confirm:$false -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
