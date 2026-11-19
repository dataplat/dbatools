#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbForeignKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess
Describe "Native foreign key behavior" -Tag IntegrationTests {
    BeforeAll {
        $foreignKeyDatabase = $null
        $foreignKeySecondServer = $null
        $foreignKeyListener = $null
        $foreignKeyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $foreignKeyDatabaseName = "native_foreign_key_$([Guid]::NewGuid().ToString("N"))"
        $foreignKeyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $foreignKeyServer, $foreignKeyDatabaseName
        $foreignKeyDatabase.Create()
        $foreignKeyDatabase.ExecuteNonQuery(@"
CREATE SCHEMA fk_native;
"@)
        $foreignKeyDatabase.ExecuteNonQuery(@"
CREATE TABLE fk_native.parent_row (id int NOT NULL CONSTRAINT pk_native_parent PRIMARY KEY);
CREATE TABLE fk_native.child_row (id int NOT NULL, parent_id int NULL,
    CONSTRAINT fk_native_child FOREIGN KEY (parent_id) REFERENCES fk_native.parent_row(id));
"@)
        $foreignKeyServer.Databases.Refresh()
        $foreignKeyDatabase = $foreignKeyServer.Databases[$foreignKeyDatabaseName]
        $splatForeignKeySecondConnection = @{
            SqlInstance         = $foreignKeyServer
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $foreignKeySecondServer = Connect-DbaInstance @splatForeignKeySecondConnection
        if ([object]::ReferenceEquals($foreignKeyServer, $foreignKeySecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        # Reserve a non-SQL endpoint so the failing connection cannot hit another service.
        $foreignKeyListener = New-Object Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Loopback), 0
        $foreignKeyListener.Start()
        $foreignKeyPort = $foreignKeyListener.LocalEndpoint.Port
        $foreignKeyBadInstance = "Data Source=tcp:127.0.0.1,$foreignKeyPort;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    AfterAll {
        if ($foreignKeyListener) { $foreignKeyListener.Stop() }
        if ($foreignKeySecondServer) { $foreignKeySecondServer.ConnectionContext.Disconnect() }
        if ($foreignKeyDatabase -and $foreignKeyDatabaseName) {
            $foreignKeyServer.Databases.Refresh()
            if ($foreignKeyServer.Databases[$foreignKeyDatabaseName]) {
                $foreignKeyServer.KillDatabase($foreignKeyDatabaseName)
            }
        }
    }

    It "preserves typed foreign keys, replaces metadata, and applies exact database filters" -Tag "NativeChecklist:switch-false" {
        $foreignKeyFixture = $foreignKeyDatabase.Tables["child_row", "fk_native"].ForeignKeys["fk_native_child"]
        foreach ($foreignKeyProperty in @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Table")) {
            $splatForeignKeyStaleProperty = @{
                InputObject = $foreignKeyFixture
                MemberType  = "NoteProperty"
                Name        = $foreignKeyProperty
                Value       = "stale"
                Force       = $true
            }
            Add-Member @splatForeignKeyStaleProperty
        }
        $splatForeignKeyMetadata = @{
            SqlInstance        = $foreignKeyServer
            Database           = $foreignKeyDatabaseName.ToUpperInvariant()
            ExcludeSystemTable = $false
            EnableException    = $true
        }
        $foreignKeyRows = @(Get-DbaDbForeignKey @splatForeignKeyMetadata)
        $foreignKeyRows.Count | Should -Be 1
        $foreignKeyRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ForeignKey
        $foreignKeyRows[0].ComputerName | Should -BeExactly $foreignKeyServer.ComputerName
        $foreignKeyRows[0].InstanceName | Should -BeExactly $foreignKeyServer.ServiceName
        $foreignKeyRows[0].SqlInstance | Should -BeExactly $foreignKeyServer.DomainInstanceName
        $foreignKeyRows[0].Database | Should -BeExactly $foreignKeyDatabaseName
        $foreignKeyRows[0].Schema | Should -BeExactly "fk_native"
        $foreignKeyRows[0].Table | Should -BeExactly "child_row"
        $foreignKeyRows[0].ReferencedTable | Should -BeExactly "parent_row"
        $foreignKeyRows[0].ReferencedTableSchema | Should -BeExactly "fk_native"
        ($foreignKeyRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,Table,ID,CreateDate,DateLastModified,Name,IsEnabled,IsChecked,NotForReplication,ReferencedKey,ReferencedTable,ReferencedTableSchema"
        $splatForeignKeyMetadata.Database = $foreignKeyDatabaseName
        $splatForeignKeyMetadata.ExcludeDatabase = $foreignKeyDatabaseName.ToUpperInvariant()
        @(Get-DbaDbForeignKey @splatForeignKeyMetadata).Count | Should -Be 0
    }

    Context "Documented wildcard database selection and explicit false switches" {
        BeforeAll {
            # Pinned help :23 documents wildcards for -Database; :135 filters with literal -In, so the
            # documented form never took effect. Help :27-28 documents no wildcards for -ExcludeDatabase.
            # Pinned :148 uses Test-Bound, so -ExcludeSystemTable:$false still excluded system tables.
            $foreignKeyWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $foreignKeyWildcardNames = @(
                "${foreignKeyWildcardPrefix}_a"
                "${foreignKeyWildcardPrefix}_b"
                "${foreignKeyWildcardPrefix}_[a]"
            )
            $foreignKeyWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($foreignKeyWildcardName in $foreignKeyWildcardNames) {
                $foreignKeyWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $foreignKeyServer, $foreignKeyWildcardName
                $foreignKeyWildcardDatabase.Create()
                $foreignKeyWildcardCreated.Add($foreignKeyWildcardName)
                $foreignKeyWildcardDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_parent] ([id] int NOT NULL CONSTRAINT [pk_native_wc_parent] PRIMARY KEY); CREATE TABLE [dbo].[native_wc_child] ([parent_id] int NULL CONSTRAINT [fk_native_wc_child] FOREIGN KEY REFERENCES [dbo].[native_wc_parent] ([id]));")
            }
            $foreignKeySystemDatabase = $foreignKeyServer.Databases[$foreignKeyWildcardNames[0]]
            $foreignKeySystemDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_system_child] ([parent_id] int NULL CONSTRAINT [fk_native_wc_system_child] FOREIGN KEY REFERENCES [dbo].[native_wc_parent] ([id])); EXEC sys.sp_addextendedproperty @name = N'microsoft_database_tools_support', @value = 1, @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'native_wc_system_child';")
            $foreignKeySystemDatabase.Tables.Refresh()
            if (-not $foreignKeySystemDatabase.Tables["native_wc_system_child", "dbo"].IsSystemObject) {
                throw "The system-table fixture is not reported as a system object by SMO"
            }
        }

        AfterAll {
            $foreignKeyServer.Databases.Refresh()
            foreach ($foreignKeyWildcardName in $foreignKeyWildcardCreated) {
                if ($foreignKeyServer.Databases[$foreignKeyWildcardName]) {
                    $foreignKeyServer.KillDatabase($foreignKeyWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatForeignKeyWildcard = @{
                SqlInstance     = $foreignKeyServer
                Database        = "${foreignKeyWildcardPrefix}_*"
                EnableException = $true
            }
            $foreignKeyWildcardRows = @(Get-DbaDbForeignKey @splatForeignKeyWildcard)
            (($foreignKeyWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($foreignKeyWildcardNames | Sort-Object) -join ",")
            $splatForeignKeyWildcard.Database = "${foreignKeyWildcardPrefix}_?"
            $foreignKeyWildcardRows = @(Get-DbaDbForeignKey @splatForeignKeyWildcard)
            (($foreignKeyWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($foreignKeyWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "keeps bracket-only, invalid and undocumented exclusion values literal" {
            $splatForeignKeyLiteral = @{
                SqlInstance     = $foreignKeyServer
                Database        = $foreignKeyWildcardNames[2]
                EnableException = $true
            }
            $foreignKeyLiteralRows = @(Get-DbaDbForeignKey @splatForeignKeyLiteral)
            (($foreignKeyLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $foreignKeyWildcardNames[2]
            $splatForeignKeyLiteral.Database = "${foreignKeyWildcardPrefix}_[*"
            @(Get-DbaDbForeignKey @splatForeignKeyLiteral).Count | Should -Be 0
            $splatForeignKeyLiteral.Database = $foreignKeyWildcardNames
            $splatForeignKeyLiteral.ExcludeDatabase = "${foreignKeyWildcardPrefix}_?"
            $foreignKeyLiteralRows = @(Get-DbaDbForeignKey @splatForeignKeyLiteral)
            (($foreignKeyLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($foreignKeyWildcardNames | Sort-Object) -join ",")
        }

        It "includes system tables when -ExcludeSystemTable is explicitly false" -Tag "NativeChecklist:switch-false" {
            $splatForeignKeySystem = @{
                SqlInstance     = $foreignKeyServer
                Database        = $foreignKeyWildcardNames[0]
                EnableException = $true
            }
            $foreignKeyBoth = "fk_native_wc_child,fk_native_wc_system_child"
            ((@(Get-DbaDbForeignKey @splatForeignKeySystem).Name | Sort-Object) -join ",") | Should -BeExactly $foreignKeyBoth
            ((@(Get-DbaDbForeignKey @splatForeignKeySystem -ExcludeSystemTable:$false).Name | Sort-Object) -join ",") | Should -BeExactly $foreignKeyBoth
            ((@(Get-DbaDbForeignKey @splatForeignKeySystem -ExcludeSystemTable).Name | Sort-Object) -join ",") | Should -BeExactly "fk_native_wc_child"
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :23 documents -Database wildcards; pinned Remove-DbaDbData.ps1:140 passes a real $db.Name): a value equal to a real database name stays
            # literal, so a caller passing a real name containing * or ? never reaches other databases.
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
            $foreignKeyRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $foreignKeyRealNameNames = @("${foreignKeyRealNamePrefix}_*", "${foreignKeyRealNamePrefix}_?", "${foreignKeyRealNamePrefix}_x")
            $foreignKeyRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($foreignKeyRealNameIndex in 0, 1, 2) {
                $foreignKeyRealNameName = $foreignKeyRealNameNames[$foreignKeyRealNameIndex]
                $foreignKeyRealNameDatabase = New-NativeWildcardNameDatabase -Server $foreignKeyServer -Name $foreignKeyRealNameName -FileStem ("${foreignKeyRealNamePrefix}_file" + $foreignKeyRealNameIndex)
                $foreignKeyRealNameCreated.Add($foreignKeyRealNameName)
                $foreignKeyRealNameDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_parent] ([id] int NOT NULL CONSTRAINT [pk_native_wc_parent] PRIMARY KEY); CREATE TABLE [dbo].[native_wc_child] ([parent_id] int NULL CONSTRAINT [fk_native_wc_child] FOREIGN KEY REFERENCES [dbo].[native_wc_parent] ([id]));")
            }
        }

        AfterAll {
            $foreignKeyServer.Databases.Refresh()
            foreach ($foreignKeyRealNameName in $foreignKeyRealNameCreated) {
                if ($foreignKeyServer.Databases[$foreignKeyRealNameName]) {
                    $foreignKeyServer.KillDatabase($foreignKeyRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatForeignKeyRealNameExact = @{
                SqlInstance     = $foreignKeyServer
                Database        = $foreignKeyRealNameNames[0]
                EnableException = $true
            }
            $foreignKeyRealNameRows = @(Get-DbaDbForeignKey @splatForeignKeyRealNameExact)
            (($foreignKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $foreignKeyRealNameNames[0]
            $splatForeignKeyRealNameExact.Database = $foreignKeyRealNameNames[1].ToUpperInvariant()
            $foreignKeyRealNameRows = @(Get-DbaDbForeignKey @splatForeignKeyRealNameExact)
            (($foreignKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $foreignKeyRealNameNames[1]
            $splatForeignKeyRealNameExact.Database = $foreignKeyRealNameNames[0, 1]
            $foreignKeyRealNameRows = @(Get-DbaDbForeignKey @splatForeignKeyRealNameExact)
            (($foreignKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($foreignKeyRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatForeignKeyRealNamePattern = @{
                SqlInstance     = $foreignKeyServer
                Database        = "${foreignKeyRealNamePrefix}*"
                EnableException = $true
            }
            $foreignKeyRealNameRows = @(Get-DbaDbForeignKey @splatForeignKeyRealNamePattern)
            (($foreignKeyRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($foreignKeyRealNameNames | Sort-Object) -join ",")
        }
    }

    It "warns and continues with distinct pipeline records around a failed connection" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $foreignKeyWarnings = @()
        $foreignKeyPreviousErrors = @($global:Error)
        $splatForeignKeyPipeline = @{
            Database        = $foreignKeyDatabaseName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "foreignKeyWarnings"
        }
        $foreignKeyPipelineRows = @(
            @($foreignKeyServer, $foreignKeyBadInstance, $foreignKeySecondServer) |
                Get-DbaDbForeignKey @splatForeignKeyPipeline
        )
        $foreignKeyPipelineRows.Count | Should -Be 2
        [object]::ReferenceEquals($foreignKeyPipelineRows[0].Parent.Parent.Parent, $foreignKeyServer) | Should -BeTrue
        [object]::ReferenceEquals($foreignKeyPipelineRows[1].Parent.Parent.Parent, $foreignKeySecondServer) | Should -BeTrue
        ($foreignKeyWarnings -join " ") | Should -BeLike "*Failure*"
        $foreignKeyConnectionError = $global:Error | Where-Object {
            $foreignKeyPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbForeignKey*"
        } | Select-Object -First 1
        $foreignKeyConnectionError | Should -Not -BeNullOrEmpty
        $foreignKeyConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "terminates at the failed pipeline connection when EnableException is set" -Tag "NativeChecklist:enable-exception" {
        $foreignKeyObserved = New-Object System.Collections.ArrayList
        $foreignKeyTerminatingError = $null
        $splatForeignKeyException = @{
            Database        = $foreignKeyDatabaseName
            EnableException = $true
        }
        try {
            @($foreignKeyServer, $foreignKeyBadInstance, $foreignKeySecondServer) |
                Get-DbaDbForeignKey @splatForeignKeyException |
                ForEach-Object { $null = $foreignKeyObserved.Add($PSItem) }
        } catch {
            $foreignKeyTerminatingError = $PSItem
        }
        $foreignKeyTerminatingError | Should -Not -BeNullOrEmpty
        $foreignKeyTerminatingError.CategoryInfo.Category | Should -Be "ConnectionError"
        $foreignKeyTerminatingError.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbForeignKey*"
        $foreignKeyTerminatingError.Exception.Message | Should -Match "^The wait operation timed out\.?$"
        $foreignKeyObserved.Count | Should -Be 1
        [object]::ReferenceEquals($foreignKeyObserved[0].Parent.Parent.Parent, $foreignKeyServer) | Should -BeTrue
    }
}

Describe "Native Get-DbaDbForeignKey numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeForeignKeyNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeForeignKeyNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeForeignKeyNumberNames = @("0$nativeForeignKeyNumber", "$nativeForeignKeyNumber")
        $nativeForeignKeyNumberCreated = @()
        foreach ($nativeForeignKeyNumberName in $nativeForeignKeyNumberNames) {
            $nativeForeignKeyNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeForeignKeyNumberServer, $nativeForeignKeyNumberName
            $nativeForeignKeyNumberDatabase.Create()
            $nativeForeignKeyNumberCreated += $nativeForeignKeyNumberName
            $nativeForeignKeyNumberDatabase.ExecuteNonQuery(@"
CREATE TABLE [dbo].[native_number_parent] ([id] int NOT NULL CONSTRAINT [pk_native_number_parent] PRIMARY KEY);
CREATE TABLE [dbo].[native_number_child] ([parent_id] int NULL,
    CONSTRAINT [fk_native_number_child] FOREIGN KEY ([parent_id]) REFERENCES [dbo].[native_number_parent] ([id]));
"@)
        }
    }

    AfterAll {
        if ($nativeForeignKeyNumberCreated.Count -gt 0) {
            $splatRemoveNativeForeignKeyNumberDatabase = @{
                SqlInstance     = $nativeForeignKeyNumberServer
                Database        = $nativeForeignKeyNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeForeignKeyNumberDatabase
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeForeignKeyNumberInclude = @{
            SqlInstance     = $nativeForeignKeyNumberServer
            Database        = [int]$nativeForeignKeyNumber
            EnableException = $true
        }
        $nativeForeignKeyNumberIncluded = @(Get-DbaDbForeignKey @splatNativeForeignKeyNumberInclude)
        (($nativeForeignKeyNumberIncluded.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeForeignKeyNumberNames | Sort-Object) -join ",")

        $splatNativeForeignKeyNumberExclude = @{
            SqlInstance     = $nativeForeignKeyNumberServer
            Database        = $nativeForeignKeyNumberNames
            ExcludeDatabase = [int]$nativeForeignKeyNumber
            EnableException = $true
        }
        @(Get-DbaDbForeignKey @splatNativeForeignKeyNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbForeignKey on Azure SQL Database" -Tag IntegrationTests {
    It "reads a foreign key in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
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
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: unique names and cleanup.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azureParentName = "native_fk_parent_$azureSuffix"
        $azureChildName = "native_fk_child_$azureSuffix"
        $azureKeyName = "native_fk_$azureSuffix"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureParentName] ([Id] int NOT NULL CONSTRAINT [PK_$azureParentName] PRIMARY KEY);")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureChildName] ([ParentId] int NULL CONSTRAINT [$azureKeyName] FOREIGN KEY REFERENCES [dbo].[$azureParentName] ([Id]));")
            $splatAzureForeignKey = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbForeignKey @splatAzureForeignKey | Where-Object Name -eq $azureKeyName)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.ForeignKey
            $azureRows[0].Parent.Name | Should -BeExactly $azureChildName
            $azureRows[0].ReferencedTable | Should -BeExactly $azureParentName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureChildName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureChildName]; IF OBJECT_ID(N'[dbo].[$azureParentName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureParentName];")
        }
    }
}

Describe "Native Get-DbaDbForeignKey over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_fk_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_login_parent] ([Id] int NOT NULL PRIMARY KEY); CREATE TABLE [dbo].[native_login_child] ([ParentId] int NULL CONSTRAINT [native_login_fk] FOREIGN KEY REFERENCES [dbo].[native_login_parent] ([Id]));")
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
            $splatLoginForeignKey = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbForeignKey @splatLoginForeignKey)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "native_login_fk"
            $loginRows[0].ReferencedTable | Should -BeExactly "native_login_parent"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbForeignKey @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbForeignKey -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
