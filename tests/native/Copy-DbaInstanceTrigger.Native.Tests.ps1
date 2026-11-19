#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaInstanceTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; Destination is an explicit array, covered below.
# NativeChecklist: sql-login N/A -- the pinned function declares SourceSqlCredential and DestinationSqlCredential, not SqlCredential.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database has no server-level or logon triggers: only sys.triggers is available there, not sys.server_triggers (https://learn.microsoft.com/sql/relational-databases/triggers/manage-trigger-security). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaInstanceTrigger" -Tag IntegrationTests {
    BeforeAll {
        $nativeSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        # Unique per leg and run. DDL triggers on CREATE_CREDENTIAL only print, so they never get in the way of a logon.
        $nativePrefix = "dbatoolsci_nativetrg_" + [Guid]::NewGuid().ToString("N")
        $nativePlain = $nativePrefix + "_plain"
        $nativeWords = $nativePrefix + "_words"
        $nativeOff = $nativePrefix + "_off"
        $nativeMissing = $nativePrefix + "_missing"
        $nativeNames = @($nativePlain, $nativeWords, $nativeOff)

        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [$nativePlain] ON ALL SERVER FOR CREATE_CREDENTIAL AS PRINT 'native trigger copy';")
        # The body names the words the pinned function rewrites in the scripted text.
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [$nativeWords] ON ALL SERVER FOR CREATE_CREDENTIAL AS PRINT 'audited: create table, then enable trigger';")
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [$nativeOff] ON ALL SERVER FOR CREATE_CREDENTIAL AS PRINT 'native disabled trigger';")
        $nativeSource.ConnectionContext.ExecuteNonQuery("DISABLE TRIGGER [$nativeOff] ON ALL SERVER;")
        $nativeSource.Triggers.Refresh()

        # The trigger as the server stores it: definition text and enabled state.
        $nativeReadTrigger = {
            param($Server, $Name)
            $query = "SELECT t.is_disabled AS IsDisabled, m.definition AS Definition FROM sys.server_triggers AS t JOIN sys.server_sql_modules AS m ON m.object_id = t.object_id WHERE t.name = N'$Name';"
            $rows = @($Server.ConnectionContext.ExecuteWithResults($query).Tables[0].Rows)
            if ($rows.Count -eq 1) { $rows[0] }
        }
        $nativeDropTrigger = {
            param($Server, $Name)
            $Server.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'$Name') DROP TRIGGER [$Name] ON ALL SERVER;")
        }
    }

    AfterEach {
        foreach ($nativeName in $nativeNames) {
            & $nativeDropTrigger $nativeDestination $nativeName
        }
        $nativeDestination.Triggers.Refresh()
    }

    AfterAll {
        foreach ($nativeName in $nativeNames) {
            if ($nativeSource) { & $nativeDropTrigger $nativeSource $nativeName }
            if ($nativeDestination) { & $nativeDropTrigger $nativeDestination $nativeName }
        }
    }

    It "copies the selected trigger with the pinned MigrationObject shape" {
        $splatCopyPlain = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerTrigger   = $nativePlain
            EnableException = $true
        }
        $nativeResults = @(Copy-DbaInstanceTrigger @splatCopyPlain)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        $nativeResults[0].Name | Should -BeExactly $nativePlain
        $nativeResults[0].Type | Should -BeExactly "Server Trigger"
        $nativeResults[0].SourceServer | Should -BeExactly $nativeSource.Name
        $nativeResults[0].DestinationServer | Should -BeExactly $nativeDestination.Name
        $nativeResults[0].Notes | Should -BeNullOrEmpty
        $nativeResults[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $nativeResults[0].PSObject.TypeNames[0] | Should -BeExactly "dbatools.MigrationObject"
        ($nativeResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
        ($nativeResults[0].PSObject.Properties.Name -join ",") | Should -BeExactly "SourceServer,DestinationServer,Name,Type,Status,Notes,DateTime"
        $nativeCopied = & $nativeReadTrigger $nativeDestination $nativePlain
        $nativeCopied.Definition | Should -BeLikeExactly "*PRINT 'native trigger copy';*"
        $nativeCopied.IsDisabled | Should -BeFalse
    }

    It "skips an existing trigger without Force and replaces it with Force" -Tag NativeChecklist:switch-false {
        $splatCopyForce = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerTrigger   = $nativePlain
            Force           = $false
            EnableException = $true
        }
        @(Copy-DbaInstanceTrigger @splatCopyForce)[0].Status | Should -BeExactly "Successful"
        $nativeSkipped = @(Copy-DbaInstanceTrigger @splatCopyForce)
        $nativeSkipped.Count | Should -Be 1
        $nativeSkipped[0].Status | Should -BeExactly "Skipped"
        $nativeSkipped[0].Notes | Should -BeExactly "Already exists on destination"

        $nativePreference = $ConfirmPreference
        $splatCopyForce.Force = $true
        $nativeReplaced = @(Copy-DbaInstanceTrigger @splatCopyForce)
        $nativeReplaced.Count | Should -Be 1
        $nativeReplaced[0].Status | Should -BeExactly "Successful"
        $ConfirmPreference | Should -Be $nativePreference
        (& $nativeReadTrigger $nativeDestination $nativePlain).Definition | Should -BeLikeExactly "*PRINT 'native trigger copy';*"
    }

    It "lets ExcludeServerTrigger win over ServerTrigger and ignores names the source does not have" {
        $splatCopyExclude = @{
            Source               = $TestConfig.InstanceCopy1
            Destination          = $TestConfig.InstanceCopy2
            ServerTrigger        = @($nativePlain, $nativeOff, $nativeMissing)
            ExcludeServerTrigger = $nativeOff
            EnableException      = $true
        }
        $nativeResults = @(Copy-DbaInstanceTrigger @splatCopyExclude)
        ($nativeResults.Name -join ",") | Should -BeExactly $nativePlain
        & $nativeReadTrigger $nativeDestination $nativeOff | Should -BeNullOrEmpty
    }

    It "does not create a trigger under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $splatCopyWhatIf = @{
            Source        = $TestConfig.InstanceCopy1
            Destination   = $TestConfig.InstanceCopy2
            ServerTrigger = $nativePlain
            Force         = $true
            WhatIf        = $true
        }
        @(Copy-DbaInstanceTrigger @splatCopyWhatIf).Count | Should -Be 0
        & $nativeReadTrigger $nativeDestination $nativePlain | Should -BeNullOrEmpty
    }

    It "continues to a valid destination after a connection failure" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $nativeWarnings = @()
        $splatCopyFailure = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = @("TCP:127.0.0.1,1", $TestConfig.InstanceCopy2)
            ServerTrigger   = $nativePlain
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWarnings"
        }
        $nativeResults = @(Copy-DbaInstanceTrigger @splatCopyFailure)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for an unreachable destination under EnableException" -Tag NativeChecklist:enable-exception {
        $nativeCaught = $null
        try {
            $null = Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination "TCP:127.0.0.1,1" -ServerTrigger $nativePlain -EnableException
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "copies a trigger whose body contains the words CREATE and ENABLE TRIGGER with its definition unchanged" {
        $nativeResults = @(Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ServerTrigger $nativeWords)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        $nativeCopied = & $nativeReadTrigger $nativeDestination $nativeWords
        $nativeCopied | Should -Not -BeNullOrEmpty
        # The body as written: the pinned rewrite would cut it at "create " and upper-case it.
        $nativeCopied.Definition | Should -BeLikeExactly "*PRINT 'audited: create table, then enable trigger';*"
        $nativeCopied.IsDisabled | Should -BeFalse
    }

    It "copies a disabled trigger as disabled with its definition unchanged" {
        $nativeResults = @(Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ServerTrigger $nativeOff)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        $nativeCopied = & $nativeReadTrigger $nativeDestination $nativeOff
        $nativeCopied | Should -Not -BeNullOrEmpty
        $nativeCopied.IsDisabled | Should -BeTrue
        # SMO scripts DISABLE TRIGGER as its own batch; it must not end up inside the copied body.
        $nativeCopied.Definition | Should -BeLikeExactly "*PRINT 'native disabled trigger';*"
        $nativeCopied.Definition | Should -Not -BeLike "*DISABLE TRIGGER*"
    }
}

Describe "Native Copy-DbaInstanceTrigger refuses Azure SQL Database" -Tag IntegrationTests {
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
        $azureTriggerName = "dbatoolsci_nativetrg_azure_" + [Guid]::NewGuid().ToString("N")
    }

    It "refuses an Azure SQL Database destination with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureDestination = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $azureServer
            ServerTrigger   = $azureTriggerName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaInstanceTrigger @splatAzureDestination).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses an Azure SQL Database source with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureSource = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            ServerTrigger   = $azureTriggerName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaInstanceTrigger @splatAzureSource).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for an Azure SQL Database destination under EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination $azureServer -ServerTrigger $azureTriggerName -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

# The shared connection layer refuses instances older than SQL Server 2008 as dbatools PR 10813 (head d8d01159) does in
# Connect-DbaInstance. An operator requirement, not a pin correction: harness-edits.md, "SQL Server 2005 refusal ported
# from PR 10813", point 3 lists these cases, on $TestConfig.InstanceLegacy with Windows authentication. This Describe
# stands alone: it uses nothing from the blocks above, and creates nothing on any instance.
Describe "Native Connect-DbaInstance refuses instances older than SQL Server 2008" -Tag IntegrationTests {
    BeforeAll {
        $legacyInstance = $TestConfig.InstanceLegacy
        # Connect-DbaInstance is the thing under test and refuses this instance, so the version is read over a plain
        # SqlConnection that does not go through it. SQL Server 2005 negotiates TLS 1.0 at most, so only the login is encrypted.
        $legacyBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        $legacyBuilder["Data Source"] = $legacyInstance
        $legacyBuilder["Integrated Security"] = $true
        $legacyBuilder["Encrypt"] = $false
        $legacyBuilder["Trust Server Certificate"] = $true
        $legacyConnection = New-Object Microsoft.Data.SqlClient.SqlConnection($legacyBuilder.ConnectionString)
        try {
            $legacyConnection.Open()
            $legacyServerVersion = $legacyConnection.ServerVersion
        } finally {
            $legacyConnection.Dispose()
        }
        # The pull request's exact message for version 9, with only the server name left open, so the TLS 1.0 security
        # warning or an SMO error can never satisfy it.
        $legacyRefusal = "\[[^\]]+\] " + [regex]::Escape("runs SQL Server 2005, which dbatools no longer supports: since 2.8.3, dbatools uses SMO 181, which requires SQL Server 2008 or later. The last release that supports SQL Server 2005 is dbatools 2.8.2 with dbatools.library 2025.12.28. See https://github.com/dataplat/dbatools#sql-server-2000-and-2005") + "$"
    }

    It "points at a real SQL Server 2005 instance" {
        # Pointed at anything newer the tests below would fail; pointed at an older one they would say nothing about 2005.
        $legacyServerVersion | Should -Match "^09\."
    }

    It "refuses the connection and names the last release that supports it" {
        $legacyCaught = $null
        try {
            $null = Connect-DbaInstance -SqlInstance $legacyInstance
        } catch {
            $legacyCaught = $PSItem
        }
        $legacyCaught | Should -Not -BeNullOrEmpty
        $legacyCaught.Exception.Message | Should -Match $legacyRefusal
    }

    It "warns instead of throwing when exceptions are disabled" {
        $legacyWarnings = @()
        $splatLegacyConnect = @{
            SqlInstance      = $legacyInstance
            DisableException = $true
            WarningVariable  = "legacyWarnings"
            WarningAction    = "SilentlyContinue"
        }
        @(Connect-DbaInstance @splatLegacyConnect).Count | Should -Be 0
        $legacyRefusals = @($legacyWarnings | Where-Object { "$PSItem" -match "runs SQL Server 2005" })
        $legacyRefusals.Count | Should -Be 1
        "$($legacyRefusals[0])" | Should -Match $legacyRefusal
    }

    It "stops a command before it reaches SMO's own queries" {
        # Without the refusal, Get-DbaDatabase failed on "Invalid column name 'is_cdc_enabled'" and the SMO collections on
        # "'CONNECTIONPROPERTY' is not a recognized built-in function name", neither of which says the instance is too old.
        $legacyCaught = $null
        try {
            $null = Get-DbaDatabase -SqlInstance $legacyInstance -EnableException
        } catch {
            $legacyCaught = $PSItem
        }
        $legacyCaught | Should -Not -BeNullOrEmpty
        $legacyCaught.Exception.Message | Should -Match "runs SQL Server 2005"
        $legacyCaught.Exception.Message | Should -Not -Match "is_cdc_enabled|CONNECTIONPROPERTY"
    }

    It "still connects to SQL Server 2008 or later without MinimumVersion" {
        $modernServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $modernServer | Should -Not -BeNullOrEmpty
        $modernServer.VersionMajor | Should -BeGreaterOrEqual 10
    }
}
