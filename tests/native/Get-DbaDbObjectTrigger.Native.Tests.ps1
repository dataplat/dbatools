#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbObjectTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native Get-DbaDbObjectTrigger behavior" -Tag IntegrationTests {
    BeforeAll {
        $objectTriggerCreated = $false
        $objectTriggerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $objectTriggerDatabaseName = "native_objtrig_" + [Guid]::NewGuid().ToString("N")
        $objectTriggerDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $objectTriggerServer, $objectTriggerDatabaseName
        $objectTriggerDatabase.Create()
        $objectTriggerCreated = $true
        $objectTriggerDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_objtrig_table] ([id] int);")
        $objectTriggerDatabase.ExecuteNonQuery("CREATE TRIGGER [dbo].[native_objtrig_ontable] ON [dbo].[native_objtrig_table] AFTER INSERT AS BEGIN SET NOCOUNT ON; END")
        $objectTriggerDatabase.ExecuteNonQuery("CREATE VIEW [dbo].[native_objtrig_view] AS SELECT [id] FROM [dbo].[native_objtrig_table];")
        $objectTriggerDatabase.ExecuteNonQuery("CREATE TRIGGER [dbo].[native_objtrig_onview] ON [dbo].[native_objtrig_view] INSTEAD OF INSERT AS BEGIN SET NOCOUNT ON; END")

        $splatObjectTriggerTable = @{
            SqlInstance     = $objectTriggerServer
            Database        = $objectTriggerDatabaseName
            Table           = "native_objtrig_table"
            EnableException = $true
        }
        $objectTriggerTable = Get-DbaDbTable @splatObjectTriggerTable
        $splatObjectTriggerView = @{
            SqlInstance     = $objectTriggerServer
            Database        = $objectTriggerDatabaseName
            View            = "native_objtrig_view"
            EnableException = $true
        }
        $objectTriggerView = Get-DbaDbView @splatObjectTriggerView
        $objectTriggerDisplay = "ComputerName,InstanceName,SqlInstance,Name,Parent,IsEnabled,DateLastModified"
    }

    AfterAll {
        if ($objectTriggerCreated) {
            $splatRemoveObjectTriggerDatabase = @{
                SqlInstance     = $objectTriggerServer
                Database        = $objectTriggerDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveObjectTriggerDatabase
        }
    }

    It "returns the triggers of every piped table and view and warns for a non-table record between them" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $objectTriggerWarnings = @()
        $splatObjectTriggerPiped = @{
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "objectTriggerWarnings"
        }
        $objectTriggerRows = @(@($objectTriggerTable, "native_objtrig_not_a_table", $objectTriggerView) | Get-DbaDbObjectTrigger @splatObjectTriggerPiped)
        ($objectTriggerRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable,native_objtrig_onview"
        $objectTriggerRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Trigger
        $objectTriggerRows[0].Parent | Should -BeOfType Microsoft.SqlServer.Management.Smo.Table
        $objectTriggerRows[1].Parent | Should -BeOfType Microsoft.SqlServer.Management.Smo.View
        foreach ($objectTriggerRow in $objectTriggerRows) {
            $objectTriggerRow.IsEnabled | Should -Be $true
            $objectTriggerRow.ComputerName | Should -BeExactly $objectTriggerRow.Parent.ComputerName
            $objectTriggerRow.InstanceName | Should -BeExactly $objectTriggerServer.ServiceName
            $objectTriggerRow.SqlInstance | Should -BeExactly $objectTriggerServer.DomainInstanceName
            ($objectTriggerRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $objectTriggerDisplay
        }
        @($objectTriggerWarnings).Count | Should -Be 1
        ($objectTriggerWarnings -join " ") | Should -BeLike "*InputObject native_objtrig_not_a_table is not of type Table or View.*"
    }

    It "terminates at a non-table record under EnableException and keeps the earlier output" -Tag "NativeChecklist:enable-exception" {
        $objectTriggerEarlier = New-Object "System.Collections.Generic.List[object]"
        $objectTriggerCaught = $null
        try {
            @($objectTriggerTable, "native_objtrig_not_a_table", $objectTriggerView) |
                Get-DbaDbObjectTrigger -EnableException |
                ForEach-Object { $objectTriggerEarlier.Add($PSItem) }
        } catch {
            $objectTriggerCaught = $PSItem
        }
        $objectTriggerEarlier.Count | Should -Be 1
        $objectTriggerEarlier[0].Name | Should -BeExactly "native_objtrig_ontable"
        $objectTriggerCaught | Should -Not -BeNullOrEmpty
        $objectTriggerCaught.Exception.Message | Should -BeLike "*InputObject native_objtrig_not_a_table is not of type Table or View.*"
    }

    It "decorates the gathered tables and views as Get-DbaDbTable and Get-DbaDbView do" {
        $splatObjectTriggerGathered = @{
            SqlInstance     = $objectTriggerServer
            Database        = $objectTriggerDatabaseName
            EnableException = $true
        }
        $objectTriggerRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerGathered)
        ($objectTriggerRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable,native_objtrig_onview"
        foreach ($objectTriggerRow in $objectTriggerRows) {
            $objectTriggerRow.Parent.Database | Should -BeExactly $objectTriggerDatabaseName
            $objectTriggerRow.Parent.SqlInstance | Should -BeExactly $objectTriggerServer.DomainInstanceName
            $objectTriggerRow.ComputerName | Should -Not -BeNullOrEmpty
            $objectTriggerRow.ComputerName | Should -BeExactly $objectTriggerRow.Parent.ComputerName
            $objectTriggerRow.SqlInstance | Should -BeExactly $objectTriggerServer.DomainInstanceName
        }
        $objectTriggerViewDisplay = $objectTriggerRows[1].Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ","
        $objectTriggerViewDisplay | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,CreateDate,DateLastModified,Name"
        $objectTriggerTableDisplay = @($objectTriggerRows[0].Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        ($objectTriggerTableDisplay[0..5] -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,Name"
        $objectTriggerTableDisplay[-1] | Should -BeExactly "FullTextIndex"
    }

    It "returns each listed instance's triggers once and continues past a failing instance" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $objectTriggerSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $objectTriggerListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $objectTriggerListener.Start()
            $objectTriggerFailedInstance = "127.0.0.1," + $objectTriggerListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $objectTriggerWarnings = @()
            $splatObjectTriggerInstances = @{
                SqlInstance     = @($objectTriggerServer, $objectTriggerFailedInstance, $objectTriggerServer)
                Database        = $objectTriggerDatabaseName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "objectTriggerWarnings"
            }
            $objectTriggerRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerInstances)
            ($objectTriggerRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable,native_objtrig_onview,native_objtrig_ontable,native_objtrig_onview"
            ($objectTriggerWarnings -join " ") | Should -BeLike "*Failure*"
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $objectTriggerSavedTimeout
            $objectTriggerListener.Stop()
        }
    }

    It "reads a command-line SqlInstance once across several piped records" -Tag "NativeChecklist:pipeline-multiple" {
        $splatObjectTriggerMixed = @{
            SqlInstance     = $objectTriggerServer
            Database        = $objectTriggerDatabaseName
            EnableException = $true
        }
        $objectTriggerRows = @(@($objectTriggerTable, $objectTriggerView) | Get-DbaDbObjectTrigger @splatObjectTriggerMixed)
        ($objectTriggerRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable,native_objtrig_ontable,native_objtrig_onview,native_objtrig_onview"
    }

    It "applies -Type to piped tables and views" {
        $objectTriggerPiped = @($objectTriggerTable, $objectTriggerView)
        $objectTriggerTableRows = @($objectTriggerPiped | Get-DbaDbObjectTrigger -Type Table -EnableException)
        ($objectTriggerTableRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable"
        $objectTriggerViewRows = @($objectTriggerPiped | Get-DbaDbObjectTrigger -Type View -EnableException)
        ($objectTriggerViewRows.Name -join ",") | Should -BeExactly "native_objtrig_onview"
        $objectTriggerAllRows = @($objectTriggerPiped | Get-DbaDbObjectTrigger -Type All -EnableException)
        ($objectTriggerAllRows.Name -join ",") | Should -BeExactly "native_objtrig_ontable,native_objtrig_onview"
    }

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :20 and :24 document wildcards for -Database and -ExcludeDatabase; :128 and :131
            # pass them to Get-DbaDbTable and Get-DbaDbView, whose Get-DbaDatabase matching is literal.
            $objectTriggerWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $objectTriggerWildcardNames = @(
                "${objectTriggerWildcardPrefix}_a"
                "${objectTriggerWildcardPrefix}_b"
                "${objectTriggerWildcardPrefix}_[a]"
            )
            $objectTriggerWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($objectTriggerWildcardName in $objectTriggerWildcardNames) {
                $objectTriggerWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $objectTriggerServer, $objectTriggerWildcardName
                $objectTriggerWildcardDatabase.Create()
                $objectTriggerWildcardCreated.Add($objectTriggerWildcardName)
                $objectTriggerWildcardDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_table] ([id] int);")
                $objectTriggerWildcardDatabase.ExecuteNonQuery("CREATE TRIGGER [dbo].[native_wc_trigger] ON [dbo].[native_wc_table] AFTER INSERT AS BEGIN SET NOCOUNT ON; END")
            }
        }

        AfterAll {
            $objectTriggerServer.Databases.Refresh()
            foreach ($objectTriggerWildcardName in $objectTriggerWildcardCreated) {
                if ($objectTriggerServer.Databases[$objectTriggerWildcardName]) {
                    $objectTriggerServer.KillDatabase($objectTriggerWildcardName)
                }
            }
        }

        It "selects and excludes databases by documented wildcard patterns" {
            $splatObjectTriggerWildcard = @{
                SqlInstance     = $objectTriggerServer
                Database        = "${objectTriggerWildcardPrefix}_*"
                EnableException = $true
            }
            $objectTriggerWildcardRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerWildcard)
            (($objectTriggerWildcardRows.Parent.Database | Sort-Object) -join ",") | Should -BeExactly (($objectTriggerWildcardNames | Sort-Object) -join ",")
            $splatObjectTriggerWildcard.Database = "${objectTriggerWildcardPrefix}_?"
            $objectTriggerWildcardRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerWildcard)
            (($objectTriggerWildcardRows.Parent.Database | Sort-Object) -join ",") | Should -BeExactly (($objectTriggerWildcardNames[0, 1] | Sort-Object) -join ",")
            $splatObjectTriggerWildcard.Database = "${objectTriggerWildcardPrefix}_*"
            $splatObjectTriggerWildcard.ExcludeDatabase = "${objectTriggerWildcardPrefix}_?"
            $objectTriggerWildcardRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerWildcard)
            ($objectTriggerWildcardRows.Parent.Database -join ",") | Should -BeExactly $objectTriggerWildcardNames[2]
            $objectTriggerWildcardRows[0].Name | Should -BeExactly "native_wc_trigger"
        }

        It "keeps bracket-only and invalid wildcard values literal" {
            $splatObjectTriggerLiteral = @{
                SqlInstance     = $objectTriggerServer
                Database        = $objectTriggerWildcardNames[2]
                EnableException = $true
            }
            $objectTriggerLiteralRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerLiteral)
            ($objectTriggerLiteralRows.Parent.Database -join ",") | Should -BeExactly $objectTriggerWildcardNames[2]
            $splatObjectTriggerLiteral.Database = "${objectTriggerWildcardPrefix}_[*"
            @(Get-DbaDbObjectTrigger @splatObjectTriggerLiteral).Count | Should -Be 0
            $splatObjectTriggerLiteral.Database = $objectTriggerWildcardNames
            $splatObjectTriggerLiteral.ExcludeDatabase = @($objectTriggerWildcardNames[2], "${objectTriggerWildcardPrefix}_[*")
            $objectTriggerLiteralRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerLiteral)
            (($objectTriggerLiteralRows.Parent.Database | Sort-Object) -join ",") | Should -BeExactly (($objectTriggerWildcardNames[0, 1] | Sort-Object) -join ",")
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 and :24 document wildcards for both filters): a value equal to a real
            # database name stays literal, so a caller passing a real name containing * or ? never reaches other databases.
            function New-NativeWildcardNameDatabase {
                param($Server, [string]$Name, [string]$FileStem)
                # Names with * or ? are not valid Windows file names, so the files get explicit names.
                $dataDirectory = $Server.DefaultFile
                if (-not $dataDirectory) { $dataDirectory = $Server.MasterDBPath }
                $logDirectory = $Server.DefaultLog
                if (-not $logDirectory) { $logDirectory = $Server.MasterDBLogPath }
                $separator = "\"
                if ($dataDirectory -match "/" -and $dataDirectory -notmatch "\\") { $separator = "/" }
                $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
                $fileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $database, "PRIMARY"
                $database.FileGroups.Add($fileGroup)
                $dataPath = $dataDirectory.TrimEnd("\", "/") + $separator + $FileStem + ".mdf"
                $dataFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroup, ($FileStem + "_data"), $dataPath
                $dataFile.IsPrimaryFile = $true
                $fileGroup.Files.Add($dataFile)
                $logPath = $logDirectory.TrimEnd("\", "/") + $separator + $FileStem + "_log.ldf"
                $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile -ArgumentList $database, ($FileStem + "_log"), $logPath
                $database.LogFiles.Add($logFile)
                $database.Create()
                $database
            }
            $objectTriggerRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $objectTriggerRealNameNames = @("${objectTriggerRealNamePrefix}_*", "${objectTriggerRealNamePrefix}_?", "${objectTriggerRealNamePrefix}_x")
            $objectTriggerRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($objectTriggerRealNameIndex in 0, 1, 2) {
                $objectTriggerRealNameName = $objectTriggerRealNameNames[$objectTriggerRealNameIndex]
                $objectTriggerRealNameDatabase = New-NativeWildcardNameDatabase -Server $objectTriggerServer -Name $objectTriggerRealNameName -FileStem ("${objectTriggerRealNamePrefix}_file" + $objectTriggerRealNameIndex)
                $objectTriggerRealNameCreated.Add($objectTriggerRealNameName)
                $objectTriggerRealNameDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_table] ([id] int);")
                $objectTriggerRealNameDatabase.ExecuteNonQuery("CREATE TRIGGER [dbo].[native_wc_trigger] ON [dbo].[native_wc_table] AFTER INSERT AS BEGIN SET NOCOUNT ON; END")
            }
            $objectTriggerServer.Databases.Refresh()
        }

        AfterAll {
            $objectTriggerServer.Databases.Refresh()
            foreach ($objectTriggerRealNameName in $objectTriggerRealNameCreated) {
                if ($objectTriggerServer.Databases[$objectTriggerRealNameName]) {
                    $objectTriggerServer.KillDatabase($objectTriggerRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatObjectTriggerRealNameExact = @{
                SqlInstance     = $objectTriggerServer
                Database        = $objectTriggerRealNameNames[0]
                EnableException = $true
            }
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNameExact)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $objectTriggerRealNameNames[0]
            $splatObjectTriggerRealNameExact.Database = $objectTriggerRealNameNames[1].ToUpperInvariant()
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNameExact)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $objectTriggerRealNameNames[1]
            $splatObjectTriggerRealNameExact.Database = $objectTriggerRealNameNames[0, 1]
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNameExact)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($objectTriggerRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatObjectTriggerRealNamePattern = @{
                SqlInstance     = $objectTriggerServer
                Database        = "${objectTriggerRealNamePrefix}*"
                EnableException = $true
            }
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNamePattern)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($objectTriggerRealNameNames | Sort-Object) -join ",")
            $splatObjectTriggerRealNamePattern.ExcludeDatabase = $objectTriggerRealNameNames[1]
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNamePattern)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($objectTriggerRealNameNames[0, 2] | Sort-Object) -join ",")
        }

        It "excludes only a real database whose name contains * or ? when its exact name is excluded" {
            $splatObjectTriggerRealNameExclude = @{
                SqlInstance     = $objectTriggerServer
                Database        = $objectTriggerRealNameNames
                ExcludeDatabase = $objectTriggerRealNameNames[1]
                EnableException = $true
            }
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNameExclude)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($objectTriggerRealNameNames[0, 2] | Sort-Object) -join ",")
            $splatObjectTriggerRealNameExclude.ExcludeDatabase = $objectTriggerRealNameNames[0]
            $objectTriggerRealNameRows = @(Get-DbaDbObjectTrigger @splatObjectTriggerRealNameExclude)
            (($objectTriggerRealNameRows.Parent.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($objectTriggerRealNameNames[1, 2] | Sort-Object) -join ",")
        }
    }
}

Describe "Native Get-DbaDbObjectTrigger on Azure SQL Database" -Tag IntegrationTests {
    It "reads a table trigger in Azure SQL Database by -SqlInstance and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: unique names; dropping the table drops its trigger.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azureTableName = "native_objtrig_azure_$azureSuffix"
        $azureTriggerName = "native_objtrig_azure_tr_$azureSuffix"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTableName] ([id] int);")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [dbo].[$azureTriggerName] ON [dbo].[$azureTableName] AFTER INSERT AS BEGIN SET NOCOUNT ON; END")
            $splatAzureObjectTrigger = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                Type            = "Table"
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbObjectTrigger @splatAzureObjectTrigger | Where-Object Name -eq $azureTriggerName)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Trigger
            $azureRows[0].Parent.Name | Should -BeExactly $azureTableName
            $azureServer.Databases[$TestConfig.AzureSqlDbName].Tables.Refresh()
            $azureTable = $azureServer.Databases[$TestConfig.AzureSqlDbName].Tables[$azureTableName, "dbo"]
            $azurePipedRows = @($azureTable | Get-DbaDbObjectTrigger -EnableException)
            ($azurePipedRows.Name -join ",") | Should -BeExactly $azureTriggerName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTableName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTableName];")
        }
    }
}

Describe "Native Get-DbaDbObjectTrigger over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_objtrig_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_login_table] ([id] int);")
            $loginDatabase.ExecuteNonQuery("CREATE TRIGGER [dbo].[native_login_trigger] ON [dbo].[native_login_table] AFTER INSERT AS BEGIN SET NOCOUNT ON; END")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginObjectTrigger = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbObjectTrigger @splatLoginObjectTrigger)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_trigger"
            $loginRows[0].Parent.Name | Should -BeExactly "native_login_table"
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested Get-DbaDbTable and Get-DbaDbView reads, which
            # are not given -EnableException, so they warn and the command continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbObjectTrigger @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
