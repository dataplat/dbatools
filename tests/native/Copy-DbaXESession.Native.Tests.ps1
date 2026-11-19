#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; Destination is an explicit array, covered below.
# NativeChecklist: sql-login N/A -- the pinned function declares SourceSqlCredential and DestinationSqlCredential, not SqlCredential.
# NativeChecklist: azure-sqldb N/A -- the command copies server-scoped event sessions (sys.server_event_sessions), and Azure SQL Database supports only database-scoped event sessions (https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-event-sessions-transact-sql, https://learn.microsoft.com/azure/azure-sql/database/xevent-db-diff-from-svr). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaXESession" -Tag IntegrationTests {
    BeforeAll {
        $xeSourceInstance = $TestConfig.InstanceCopy1
        $xeDestInstance = $TestConfig.InstanceCopy2
        $xeSource = Connect-DbaInstance -SqlInstance $xeSourceInstance -EnableException
        $xeDest = Connect-DbaInstance -SqlInstance $xeDestInstance -EnableException
        $xeBadInstance = "TCP:127.0.0.1,1"

        $xeSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $xeStopped = "dbatoolsci_xestopped_$xeSuffix"
        $xeRunning = "dbatoolsci_xerunning_$xeSuffix"
        $xeWhatIf = "dbatoolsci_xewhatif_$xeSuffix"
        $xeNames = @($xeStopped, $xeRunning, $xeWhatIf)

        # The names are plain letters, digits and underscores, so brackets quote them safely.
        foreach ($xeName in $xeNames) {
            $null = $xeSource.ConnectionContext.ExecuteNonQuery("CREATE EVENT SESSION [$xeName] ON SERVER ADD EVENT sqlserver.error_reported (WHERE ([severity] >= (20))) ADD TARGET package0.ring_buffer WITH (STARTUP_STATE = OFF);")
        }
        $null = $xeSource.ConnectionContext.ExecuteNonQuery("ALTER EVENT SESSION [$xeRunning] ON SERVER STATE = START;")

        function Get-XeCount ($Instance, $Query, $Name) {
            $splatXeCount = @{
                SqlInstance     = $Instance
                Database        = "master"
                Query           = $Query
                SqlParameter    = @{ name = $Name }
                EnableException = $true
            }
            [int](Invoke-DbaQuery @splatXeCount).total
        }
        $xeExistsQuery = "SELECT COUNT(*) AS total FROM sys.server_event_sessions WHERE name = @name"
        $xeRunningQuery = "SELECT COUNT(*) AS total FROM sys.dm_xe_sessions WHERE name = @name"
        $xeEventsQuery = "SELECT COUNT(*) AS total FROM sys.server_event_session_events AS e INNER JOIN sys.server_event_sessions AS s ON s.event_session_id = e.event_session_id WHERE s.name = @name"
    }

    AfterAll {
        foreach ($xeServer in @($xeSource, $xeDest)) {
            foreach ($xeName in $xeNames) {
                $null = $xeServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'$xeName') DROP EVENT SESSION [$xeName] ON SERVER;")
            }
        }
    }

    It "copies a stopped session with the pinned MigrationObject shape and explicit false switches" -Tag "NativeChecklist:switch-false" {
        $splatXeCopy = @{
            Source          = $xeSourceInstance
            Destination     = $xeDestInstance
            XeSession       = $xeStopped
            Force           = $false
            EnableException = $false
        }
        $xeResult = @(Copy-DbaXESession @splatXeCopy)
        $xeResult.Count | Should -Be 1
        $xeResult[0].Name | Should -Be $xeStopped
        $xeResult[0].Type | Should -Be "Extended Event"
        $xeResult[0].Status | Should -Be "Successful"
        $xeResult[0].Notes | Should -BeNullOrEmpty
        $xeResult[0].SourceServer | Should -Be $xeSource.Name
        $xeResult[0].DestinationServer | Should -Be $xeDest.Name
        $xeResult[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $xeResult[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        Get-XeCount -Instance $xeDestInstance -Query $xeExistsQuery -Name $xeStopped | Should -Be 1
        Get-XeCount -Instance $xeDestInstance -Query $xeRunningQuery -Name $xeStopped | Should -Be 0
    }

    It "starts a copied session that runs on the source" {
        $xeResult = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeRunning)
        $xeResult.Count | Should -Be 1
        $xeResult[0].Status | Should -Be "Successful"
        Get-XeCount -Instance $xeDestInstance -Query $xeRunningQuery -Name $xeRunning | Should -Be 1
    }

    It "skips an existing session without Force and replaces it with Force" {
        $null = $xeDest.ConnectionContext.ExecuteNonQuery("ALTER EVENT SESSION [$xeStopped] ON SERVER ADD EVENT sqlserver.sql_batch_completed;")
        Get-XeCount -Instance $xeDestInstance -Query $xeEventsQuery -Name $xeStopped | Should -Be 2

        $xeSkip = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeStopped)
        $xeSkip.Count | Should -Be 1
        $xeSkip[0].Status | Should -Be "Skipped"
        $xeSkip[0].Notes | Should -Be "Already exists on destination"
        Get-XeCount -Instance $xeDestInstance -Query $xeEventsQuery -Name $xeStopped | Should -Be 2

        $xeForce = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeStopped -Force)
        $xeForce.Count | Should -Be 1
        $xeForce[0].Status | Should -Be "Successful"
        $xeForce[0].Notes | Should -BeNullOrEmpty
        Get-XeCount -Instance $xeDestInstance -Query $xeEventsQuery -Name $xeStopped | Should -Be 1
    }

    It "changes nothing under WhatIf, with or without Force" -Tag "NativeChecklist:whatif-confirm" {
        $xeResult = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeWhatIf -WhatIf)
        $xeResult.Count | Should -Be 0
        Get-XeCount -Instance $xeDestInstance -Query $xeExistsQuery -Name $xeWhatIf | Should -Be 0

        $xeForce = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeRunning, $xeWhatIf -Force -WhatIf)
        $xeForce.Count | Should -Be 0
        Get-XeCount -Instance $xeDestInstance -Query $xeExistsQuery -Name $xeWhatIf | Should -Be 0
        Get-XeCount -Instance $xeDestInstance -Query $xeRunningQuery -Name $xeRunning | Should -Be 1
    }

    It "never copies the system_health session, even when named" {
        # Without -Force a copied system_health would show as a Skipped row, so nothing on the destination changes.
        $xeResult = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession "SYSTEM_HEALTH", $xeStopped)
        $xeResult.Count | Should -Be 1
        $xeResult[0].Name | Should -Be $xeStopped
    }

    It "lets ExcludeXeSession win over XeSession, ignoring case" {
        $xeResult = @(Copy-DbaXESession -Source $xeSourceInstance -Destination $xeDestInstance -XeSession $xeWhatIf -ExcludeXeSession $xeWhatIf.ToUpperInvariant())
        $xeResult.Count | Should -Be 0
        Get-XeCount -Instance $xeDestInstance -Query $xeExistsQuery -Name $xeWhatIf | Should -Be 0
    }

    It "continues the destination array after a connection failure" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $splatXeContinue = @{
            Source          = $xeSourceInstance
            Destination     = @($xeBadInstance, $xeDestInstance)
            XeSession       = $xeStopped
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "xeWarning"
        }
        $xeResult = @(Copy-DbaXESession @splatXeContinue)
        $xeResult.Count | Should -Be 1
        $xeResult[0].Status | Should -Be "Skipped"
        $xeResult[0].DestinationServer | Should -Be $xeDest.Name
        ($xeWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for a failing destination when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        $xeError = $null
        try {
            $null = Copy-DbaXESession -Source $xeSourceInstance -Destination $xeBadInstance -XeSession $xeStopped -EnableException
        } catch {
            $xeError = $PSItem
        }
        $xeError | Should -Not -BeNullOrEmpty
        $xeError.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
    }

    It "warns and copies nothing when the source cannot be reached" {
        $xeResult = @(Copy-DbaXESession -Source $xeBadInstance -Destination $xeDestInstance -XeSession $xeWhatIf -WarningAction SilentlyContinue -WarningVariable xeWarning)
        $xeResult.Count | Should -Be 0
        ($xeWarning -join " ") | Should -BeLike "*Failure*"
        Get-XeCount -Instance $xeDestInstance -Query $xeExistsQuery -Name $xeWhatIf | Should -Be 0
    }
}

Describe "Native Copy-DbaXESession refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        # A name no instance has, so nothing is ever copied by these tests.
        $azureSessionName = "dbatoolsci_xeazure_" + [Guid]::NewGuid().ToString("N")
    }

    It "refuses an Azure SQL Database source with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureSource = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            XeSession       = $azureSessionName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaXESession @splatAzureSource).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses an Azure SQL Database destination with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureDestination = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $azureServer
            XeSession       = $azureSessionName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaXESession @splatAzureDestination).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws the refusal as a connection error for an Azure SQL Database destination under EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaXESession -Source $TestConfig.InstanceCopy1 -Destination $azureServer -XeSession $azureSessionName -EnableException -ErrorAction SilentlyContinue
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
