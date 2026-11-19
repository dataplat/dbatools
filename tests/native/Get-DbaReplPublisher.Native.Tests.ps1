#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplPublisher",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm

Describe "Native Get-DbaReplPublisher" -Tag IntegrationTests {
    BeforeAll {
        # Every fixture made here, so AfterAll can remove any a failed test left behind.
        $script:nativePublisherFixtures = New-Object System.Collections.ArrayList
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
            $null = $script:nativePublisherFixtures.Add($fixture)
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
        # Removes the fixture's publisher, distribution database and distributor; a second call finds nothing to remove.
        function Remove-NativePublisherFixture($fixture) {
            if (-not $fixture) { return }
            # A fresh connection, so cleanup never depends on the state the command left its own connection in.
            $fixture.Server = Connect-DbaInstance -SqlInstance $fixture.Instance -EnableException
            $fixture.Replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $fixture.Server.ConnectionContext
            $fixture.Replication.Refresh()
            if ($fixture.Replication.IsDistributor) {
                $fixture.Replication.DistributionPublishers.Refresh()
                foreach ($publisher in @($fixture.Replication.DistributionPublishers)) { $publisher.Remove($true) }
                $fixture.Replication.DistributionDatabases.Refresh()
                $database = $fixture.Replication.DistributionDatabases[$fixture.Database]
                if ($database) { $database.Remove() }
                $fixture.Replication.Refresh()
                if ($fixture.Replication.IsDistributor) { $fixture.Replication.UninstallDistributor($false) }
            }
            $name = $fixture.Database
            if ([int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$name'") -ne 0) {
                $fixture.Server.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$name]")
            }
            [int]$fixture.Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0
        }
        # The connection failure's own text, read from the record so each assertion names the real cause.
        function Get-NativeFailureCause($record) {
            $record | Should -Not -BeNullOrEmpty
            $cause = $record.Exception.GetBaseException().Message
            $cause | Should -Not -BeNullOrEmpty
            $cause
        }
        function Get-NativeExceptionChain($record) {
            $messages = @()
            for ($exception = $record.Exception; $exception; $exception = $exception.InnerException) { $messages += $exception.Message }
            $messages
        }
        # The command's own connection-failure record, as measured on the pin on both editions (evidence nondistributor-20261112):
        # its exception carries the cause itself with the SqlException beneath it. Connect-DbaInstance's "Error connecting to"
        # text appears only in that command's own warning and record, never in this command's record.
        function Assert-NativeConnectFailureRecord($record, $cause) {
            $record.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaReplPublisher*'
            $record.CategoryInfo.Category | Should -Be 'ConnectionError'
            $record.Exception.Message | Should -BeExactly $cause
            $record.Exception.InnerException.GetType().Name | Should -BeExactly 'SqlException'
            @(Get-NativeExceptionChain $record | Where-Object { $PSItem -like 'Error connecting to*' }).Count | Should -Be 0 -Because ((Get-NativeExceptionChain $record) -join ' <- ')
        }
        # Port 1 on localhost: nothing listens there, and the one-second timeout keeps the failure quick.
        $nativePublisherBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $nativePublisherDefaultView = @("ComputerName", "InstanceName", "SqlInstance", "Status", "WorkingDirectory", "DistributionDatabase", "DistributionPublications", "PublisherType", "Name")
    }

    AfterAll {
        foreach ($fixture in @($script:nativePublisherFixtures)) { Remove-NativePublisherFixture $fixture }
    }

    It "returns the instance's publisher with the pinned decorations and default view, by name and piped as a server" {
        $fixture = New-NativePublisherFixture $TestConfig.InstanceSingle
        try {
            $output = @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSingle -EnableException)
            $output.Count | Should -Be 1
            $output[0] | Should -BeOfType Microsoft.SqlServer.Replication.DistributionPublisher
            $output[0].Name | Should -Be $fixture.PublisherName
            $output[0].PublisherType | Should -Be "MSSQLSERVER"
            $output[0].DistributionDatabase | Should -Be $fixture.Database
            (@($output[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly ($nativePublisherDefaultView -join ',')
            $output[0].ComputerName | Should -Not -BeNullOrEmpty
            $output[0].InstanceName | Should -Not -BeNullOrEmpty
            $output[0].SqlInstance | Should -Not -BeNullOrEmpty

            $piped = @($fixture.Server | Get-DbaReplPublisher -EnableException)
            $piped.Count | Should -Be 1
            $piped[0].Name | Should -Be $fixture.PublisherName
        } finally { Remove-NativePublisherFixture $fixture }
    }

    It "warns with the connection failure's cause and goes on to the next pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $fixture = New-NativePublisherFixture $TestConfig.InstanceSingle
        try {
            $warnings = @()
            $errors = @()
            $output = @(@($nativePublisherBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplPublisher -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            $output.Count | Should -Be 1
            $output[0].Name | Should -Be $fixture.PublisherName
            $record = @($errors | Where-Object { $PSItem.FullyQualifiedErrorId -like 'dbatools_Get-DbaReplPublisher*' -and $PSItem.CategoryInfo.Category -eq 'ConnectionError' })[0]
            $cause = Get-NativeFailureCause $record
            $text = $warnings -join "`n"
            # The bracketed instance text is not asserted: the pin shows "[Failed to mask the connection string]" for this
            # connection-string input (evidence nondistributor-20261112), the shared native message the instance name.
            $text | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[[^\]]+\]: ' + [regex]::Escape($cause))
            $text | Should -Match ('\[Get-DbaReplPublisher\] Failure \| ' + [regex]::Escape($cause))
            Assert-NativeConnectFailureRecord $record $cause
        } finally { Remove-NativePublisherFixture $fixture }
    }

    It "stops at a connection failure with EnableException, with the connection failure's cause" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = $null
        try {
            $output = @(@($nativePublisherBadInstance, $TestConfig.InstanceSingle) | Get-DbaReplPublisher -EnableException -WarningAction SilentlyContinue)
        } catch { $failure = $_ }
        $output | Should -BeNullOrEmpty
        $cause = Get-NativeFailureCause $failure
        Assert-NativeConnectFailureRecord $failure $cause
    }

    It "returns nothing and reports nothing on an instance that is not a distributor" {
        # Measured on the pin, both editions (evidence nondistributor-20261112): no output, warning or error record, plain and
        # with EnableException.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $server.ConnectionContext
        $replication.IsDistributor | Should -BeFalse -Because 'the lab leaves InstanceSingle without a distributor'
        foreach ($enable in @($false, $true)) {
            $warnings = @()
            $errors = @()
            $output = @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSingle -EnableException:$enable -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            $output.Count | Should -Be 0 -Because "EnableException $enable"
            $warnings.Count | Should -Be 0 -Because (@($warnings) -join ' | ')
            $errors.Count | Should -Be 0 -Because (@($errors) -join ' | ')
        }
    }

    It "names the instance that failed to connect as the failure's target, not the server read before it" {
        $errors = @()
        $null = @(@($TestConfig.InstanceSingle, $nativePublisherBadInstance) | Get-DbaReplPublisher -EnableException:$false -WarningAction SilentlyContinue -ErrorVariable errors)
        $record = @($errors | Where-Object { $PSItem.FullyQualifiedErrorId -like 'dbatools_Get-DbaReplPublisher*' -and $PSItem.CategoryInfo.Category -eq 'ConnectionError' })[0]
        $null = Get-NativeFailureCause $record
        $record.TargetObject | Should -Not -BeNullOrEmpty
        $record.TargetObject | Should -Not -BeOfType Microsoft.SqlServer.Management.Smo.Server
        "$($record.TargetObject)" | Should -Match 'localhost,1'

        $errors = @()
        $null = @(Get-DbaReplPublisher -SqlInstance $nativePublisherBadInstance -EnableException:$false -WarningAction SilentlyContinue -ErrorVariable errors)
        $record = @($errors | Where-Object { $PSItem.FullyQualifiedErrorId -like 'dbatools_Get-DbaReplPublisher*' -and $PSItem.CategoryInfo.Category -eq 'ConnectionError' })[0]
        $null = Get-NativeFailureCause $record
        "$($record.TargetObject)" | Should -Match 'localhost,1'
    }

    It "authenticates with SQL credentials" -Tag "NativeChecklist:sql-login" {
        $warnings = @()
        $output = @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        ($warnings -join ' ') | Should -Not -BeLike '*Error connecting to*'
        foreach ($item in $output) { $item | Should -BeOfType Microsoft.SqlServer.Replication.DistributionPublisher }
    }

    It "rejects the SQL-login instance without credentials" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaReplPublisher.ps1, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #     $replServer = Get-DbaReplServer -SqlInstance $server -EnableException:$EnableException
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
        # Pin public/Connect-DbaInstance.ps1:499-503 and 1501-1502, verbatim:
        # if ($DisableException) {
        #     $EnableException = $false
        # } else {
        #     $EnableException = $true
        # }
        # if (-not $connectionSucceeded) {
        #     Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
        # The base already ships a cmdlet and the pin predates src/; no buildable commit runs it.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt; manager 26cdfe6de457.
        $warnings = @()
        $errors = @()
        @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSqlLogin -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
        $record = @($errors | Where-Object { $PSItem.FullyQualifiedErrorId -like 'dbatools_Get-DbaReplPublisher*' -and $PSItem.CategoryInfo.Category -eq 'ConnectionError' })[0]
        $cause = Get-NativeFailureCause $record
        $cause | Should -BeLike 'Login failed for user*'
        ($warnings -join "`n") | Should -Match ('\[Get-DbaReplPublisher\] Failure \| ' + [regex]::Escape($cause))
        $failure = $null
        try {
            $null = Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSqlLogin -EnableException -WarningAction SilentlyContinue
        } catch { $failure = $_ }
        $failure.Exception.Message | Should -BeLike 'Login failed for user*'
    }

    # NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; it cannot be a publisher or distributor: https://learn.microsoft.com/azure/azure-sql/managed-instance/replication-transactional-overview
    It "refuses Azure SQL Database before reading publishers" {
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
        @(Get-DbaReplPublisher -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join "`n") | Should -Match '\[Get-DbaReplPublisher\] Failure \| Azure SQL Database not supported'
        $failure = $null
        try {
            $null = Get-DbaReplPublisher -SqlInstance $azure -EnableException -WarningAction SilentlyContinue
        } catch { $failure = $_ }
        $failure.Exception.Message | Should -BeExactly 'Azure SQL Database not supported'
    }
}
