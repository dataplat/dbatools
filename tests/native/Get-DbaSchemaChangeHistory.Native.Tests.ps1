#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaSchemaChangeHistory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.
# NativeChecklist: azure-sqldb N/A -- the command reads the instance's default trace (sys.traces and fn_trace_gettable), and Azure SQL Database has neither SQL Trace nor a default trace (sys.traces applies to SQL Server and Azure SQL Managed Instance: https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-traces-transact-sql); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native schema change history behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeSchemaServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSchemaSuffix = [Guid]::NewGuid().ToString("N")
        # The offline database sorts first, so a later database must still be read after its failure.
        $nativeSchemaOfflineName = "native_schema_a_" + $nativeSchemaSuffix
        $nativeSchemaDatabaseName = "native_schema_b_" + $nativeSchemaSuffix
        $nativeSchemaTableName = "native_schema_table_" + $nativeSchemaSuffix
        $nativeSchemaCreated = @()
        foreach ($nativeSchemaName in @($nativeSchemaOfflineName, $nativeSchemaDatabaseName)) {
            $nativeSchemaNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSchemaServer, $nativeSchemaName
            $nativeSchemaNew.Create()
            $nativeSchemaCreated += $nativeSchemaName
        }
        $nativeSchemaServer.Databases[$nativeSchemaDatabaseName].ExecuteNonQuery("CREATE TABLE [dbo].[$nativeSchemaTableName] ([Id] int); CREATE TABLE [dbo].[native_schema_other] ([Id] int);")
        $nativeSchemaServer.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$nativeSchemaOfflineName] SET OFFLINE WITH ROLLBACK IMMEDIATE")
        $nativeSchemaServer.Databases.Refresh()
        $nativeSchemaDisplay = "ComputerName,InstanceName,SqlInstance,DatabaseName,DateModified,LoginName,UserName,ApplicationName,DDLOperation,Object,ObjectType"
    }

    AfterAll {
        if ($nativeSchemaCreated -contains $nativeSchemaOfflineName) {
            $nativeSchemaServer.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$nativeSchemaOfflineName] SET ONLINE")
        }
        if ($nativeSchemaCreated.Count -gt 0) {
            $splatRemoveNativeSchemaDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $nativeSchemaCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeSchemaDatabase
        }
    }

    It "returns the trace rows of the selected database for each piped instance with the pinned display set" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeSchemaRead = @{
            Database        = $nativeSchemaDatabaseName.ToUpperInvariant()
            Object          = $nativeSchemaTableName
            EnableException = $true
        }
        $nativeSchemaRows = @(@($nativeSchemaServer, $nativeSchemaServer) | Get-DbaSchemaChangeHistory @splatNativeSchemaRead)
        $nativeSchemaRows.Count | Should -BeGreaterThan 1
        ($nativeSchemaRows.Count % 2) | Should -Be 0
        foreach ($nativeSchemaRow in $nativeSchemaRows) {
            $nativeSchemaRow | Should -BeOfType System.Data.DataRow
            ($nativeSchemaRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeSchemaDisplay
            $nativeSchemaRow.DatabaseName | Should -BeExactly $nativeSchemaDatabaseName
            $nativeSchemaRow.Object | Should -BeExactly $nativeSchemaTableName
        }
        @($nativeSchemaRows | Where-Object DDLOperation -eq "Create").Count | Should -BeGreaterThan 1
    }

    It "applies the Since filter and excludes databases by literal name" {
        $splatNativeSchemaSince = @{
            SqlInstance     = $nativeSchemaServer
            Database        = $nativeSchemaDatabaseName
            Object          = @($nativeSchemaTableName, "native_schema_other")
            Since           = (Get-Date).AddDays(-1)
            EnableException = $true
            ErrorVariable   = "nativeSchemaSinceErrors"
        }
        $nativeSchemaRecent = @(Get-DbaSchemaChangeHistory @splatNativeSchemaSince)
        $nativeSchemaSinceErrors.Count | Should -Be 0
        @($nativeSchemaRecent.Object | Sort-Object -Unique) -join "," | Should -BeExactly ((@($nativeSchemaTableName, "native_schema_other") | Sort-Object) -join ",")
        $splatNativeSchemaSince.Since = (Get-Date).AddDays(1)
        @(Get-DbaSchemaChangeHistory @splatNativeSchemaSince).Count | Should -Be 0
        $nativeSchemaSinceErrors.Count | Should -Be 0
        $splatNativeSchemaSince.Remove("Since")
        $splatNativeSchemaSince.ExcludeDatabase = $nativeSchemaDatabaseName.ToUpperInvariant()
        @(Get-DbaSchemaChangeHistory @splatNativeSchemaSince).Count | Should -Be 0
        $splatNativeSchemaSince.ExcludeDatabase = "native_schema_*"
        @(Get-DbaSchemaChangeHistory @splatNativeSchemaSince).Count | Should -BeGreaterThan 0
    }

    It "reports a database that cannot be queried as an error and still reads the next database" {
        $nativeSchemaQueryErrors = @()
        $splatNativeSchemaOffline = @{
            SqlInstance     = $nativeSchemaServer
            Database        = @($nativeSchemaOfflineName, $nativeSchemaDatabaseName)
            Object          = $nativeSchemaTableName
            EnableException = $true
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "nativeSchemaQueryErrors"
        }
        $nativeSchemaAfterOffline = @(Get-DbaSchemaChangeHistory @splatNativeSchemaOffline)
        $nativeSchemaAfterOffline.Count | Should -BeGreaterThan 0
        @($nativeSchemaAfterOffline | Where-Object DatabaseName -ne $nativeSchemaDatabaseName).Count | Should -Be 0
        $nativeSchemaQueryErrors.Count | Should -Be 1
        $nativeSchemaQueryErrors[0].FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
        $nativeSchemaQueryErrors[0].Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
        $nativeSchemaQueryErrors[0].Exception.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s):*'
    }

    It "continues after a connection failure unless EnableException terminates while retaining earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeSchemaSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeSchemaListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeSchemaListener.Start()
            $nativeSchemaFailedInstance = "127.0.0.1," + $nativeSchemaListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeSchemaWarnings = @()
            $splatNativeSchemaFailure = @{
                Database        = $nativeSchemaDatabaseName
                Object          = $nativeSchemaTableName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeSchemaWarnings"
            }
            $nativeSchemaSingle = @(Get-DbaSchemaChangeHistory -SqlInstance $nativeSchemaServer -Database $nativeSchemaDatabaseName -Object $nativeSchemaTableName -EnableException)
            $nativeSchemaContinued = @(@($nativeSchemaServer, $nativeSchemaFailedInstance, $nativeSchemaServer) | Get-DbaSchemaChangeHistory @splatNativeSchemaFailure)
            $nativeSchemaContinued.Count | Should -Be ($nativeSchemaSingle.Count * 2)
            ($nativeSchemaWarnings -join " ") | Should -BeLike "*Failure*"

            $nativeSchemaEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeSchemaCaught = $null
            $splatNativeSchemaFailure.EnableException = $true
            try {
                @($nativeSchemaServer, $nativeSchemaFailedInstance, $nativeSchemaServer) |
                    Get-DbaSchemaChangeHistory @splatNativeSchemaFailure |
                    ForEach-Object { $nativeSchemaEarlier.Add($PSItem) }
            } catch {
                $nativeSchemaCaught = $PSItem
            }
            $nativeSchemaEarlier.Count | Should -Be $nativeSchemaSingle.Count
            $nativeSchemaCaught | Should -Not -BeNullOrEmpty
            $nativeSchemaCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeSchemaCaught.TargetObject | Should -Be $nativeSchemaFailedInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeSchemaSavedTimeout
            $nativeSchemaListener.Stop()
        }
    }
}

Describe "Native Get-DbaSchemaChangeHistory numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeNumberNames = @("0$nativeNumber", "$nativeNumber")
        # A unique table gives each fixture a trace row that no earlier database with a reused ID can match.
        $nativeNumberTableName = "native_number_table_" + [Guid]::NewGuid().ToString("N")
        $nativeNumberFixtures = @()
        foreach ($nativeNumberName in $nativeNumberNames) {
            $nativeNumberFixture = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeNumberServer, $nativeNumberName
            $nativeNumberFixture.Create()
            $nativeNumberFixtures += $nativeNumberFixture
            $nativeNumberFixture.ExecuteNonQuery("CREATE TABLE [dbo].[$nativeNumberTableName] ([Id] int);")
        }
    }

    AfterAll {
        foreach ($nativeNumberFixture in $nativeNumberFixtures) {
            $nativeNumberFixture.Drop()
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeNumberInclude = @{
            SqlInstance     = $nativeNumberServer
            Database        = [int]$nativeNumber
            Object          = $nativeNumberTableName
            EnableException = $true
        }
        $nativeNumberIncluded = @(Get-DbaSchemaChangeHistory @splatNativeNumberInclude)
        (($nativeNumberIncluded.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeNumberNames | Sort-Object) -join ",")

        $splatNativeNumberExclude = @{
            SqlInstance     = $nativeNumberServer
            Database        = $nativeNumberNames
            ExcludeDatabase = [int]$nativeNumber
            Object          = $nativeNumberTableName
            EnableException = $true
        }
        @(Get-DbaSchemaChangeHistory @splatNativeNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaSchemaChangeHistory documented wildcard database selection" -Tag IntegrationTests {
    BeforeAll {
        # Pinned help :20 documents wildcards for -Database; :125 filters with literal -in, so the documented
        # form never took effect. Help :24-25 documents no wildcards for -ExcludeDatabase, which stays literal.
        $nativeWildcardServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
        $nativeWildcardNames = @(
            "${nativeWildcardPrefix}_a"
            "${nativeWildcardPrefix}_b"
            "${nativeWildcardPrefix}_[a]"
        )
        # A unique table gives each fixture a trace row that no earlier database with a reused ID can match.
        $nativeWildcardTableName = "native_wc_table_" + [Guid]::NewGuid().ToString("N")
        $nativeWildcardCreated = New-Object System.Collections.Generic.List[string]
        foreach ($nativeWildcardName in $nativeWildcardNames) {
            $nativeWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeWildcardServer, $nativeWildcardName
            $nativeWildcardDatabase.Create()
            $nativeWildcardCreated.Add($nativeWildcardName)
            $nativeWildcardDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[$nativeWildcardTableName] ([Id] int);")
        }
    }

    AfterAll {
        $nativeWildcardServer.Databases.Refresh()
        foreach ($nativeWildcardName in $nativeWildcardCreated) {
            if ($nativeWildcardServer.Databases[$nativeWildcardName]) {
                $nativeWildcardServer.KillDatabase($nativeWildcardName)
            }
        }
    }

    It "selects databases by a documented wildcard pattern" {
        $splatNativeWildcard = @{
            SqlInstance     = $nativeWildcardServer
            Database        = "${nativeWildcardPrefix}_*"
            Object          = $nativeWildcardTableName
            EnableException = $true
        }
        $nativeWildcardRows = @(Get-DbaSchemaChangeHistory @splatNativeWildcard)
        (($nativeWildcardRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeWildcardNames | Sort-Object) -join ",")
        $splatNativeWildcard.Database = "${nativeWildcardPrefix}_?"
        $nativeWildcardRows = @(Get-DbaSchemaChangeHistory @splatNativeWildcard)
        (($nativeWildcardRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeWildcardNames[0, 1] | Sort-Object) -join ",")
    }

    It "keeps bracket-only, invalid and undocumented exclusion values literal" {
        $splatNativeWildcardLiteral = @{
            SqlInstance     = $nativeWildcardServer
            Database        = $nativeWildcardNames[2]
            Object          = $nativeWildcardTableName
            EnableException = $true
        }
        ((@(Get-DbaSchemaChangeHistory @splatNativeWildcardLiteral).DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeWildcardNames[2]
        $splatNativeWildcardLiteral.Database = "${nativeWildcardPrefix}_[*"
        @(Get-DbaSchemaChangeHistory @splatNativeWildcardLiteral).Count | Should -Be 0
        $splatNativeWildcardLiteral.Database = $nativeWildcardNames
        $splatNativeWildcardLiteral.ExcludeDatabase = "${nativeWildcardPrefix}_?"
        ((@(Get-DbaSchemaChangeHistory @splatNativeWildcardLiteral).DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeWildcardNames | Sort-Object) -join ",")
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 documents -Database wildcards): a value equal to a real database name stays
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
            $nativeRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeRealNameNames = @("${nativeRealNamePrefix}_*", "${nativeRealNamePrefix}_?", "${nativeRealNamePrefix}_x")
            $nativeRealNameCreated = New-Object System.Collections.Generic.List[string]
            # A unique table gives each fixture a trace row that no earlier database with a reused ID can match.
            $nativeRealNameTableName = "native_wc_table_" + [Guid]::NewGuid().ToString("N")
            foreach ($nativeRealNameIndex in 0, 1, 2) {
                $nativeRealNameName = $nativeRealNameNames[$nativeRealNameIndex]
                $nativeRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeWildcardServer -Name $nativeRealNameName -FileStem ("${nativeRealNamePrefix}_file" + $nativeRealNameIndex)
                $nativeRealNameCreated.Add($nativeRealNameName)
                $nativeRealNameDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[$nativeRealNameTableName] ([Id] int);")
            }
        }

        AfterAll {
            $nativeWildcardServer.Databases.Refresh()
            foreach ($nativeRealNameName in $nativeRealNameCreated) {
                if ($nativeWildcardServer.Databases[$nativeRealNameName]) {
                    $nativeWildcardServer.KillDatabase($nativeRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeRealNameExact = @{
                SqlInstance     = $nativeWildcardServer
                Database        = $nativeRealNameNames[0]
                Object          = $nativeRealNameTableName
                EnableException = $true
            }
            $nativeRealNameRows = @(Get-DbaSchemaChangeHistory @splatNativeRealNameExact)
            (($nativeRealNameRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeRealNameNames[0]
            $splatNativeRealNameExact.Database = $nativeRealNameNames[1].ToUpperInvariant()
            $nativeRealNameRows = @(Get-DbaSchemaChangeHistory @splatNativeRealNameExact)
            (($nativeRealNameRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeRealNameNames[1]
            $splatNativeRealNameExact.Database = $nativeRealNameNames[0, 1]
            $nativeRealNameRows = @(Get-DbaSchemaChangeHistory @splatNativeRealNameExact)
            (($nativeRealNameRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeRealNamePattern = @{
                SqlInstance     = $nativeWildcardServer
                Database        = "${nativeRealNamePrefix}*"
                Object          = $nativeRealNameTableName
                EnableException = $true
            }
            $nativeRealNameRows = @(Get-DbaSchemaChangeHistory @splatNativeRealNamePattern)
            (($nativeRealNameRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeRealNameNames | Sort-Object) -join ",")
            # -ExcludeDatabase documents no wildcards, so a real name in it stays literal.
            $splatNativeRealNamePattern.ExcludeDatabase = $nativeRealNameNames[1]
            $nativeRealNameRows = @(Get-DbaSchemaChangeHistory @splatNativeRealNamePattern)
            (($nativeRealNameRows.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeRealNameNames[0, 2] | Sort-Object) -join ",")
        }
    }
}

Describe "Native Get-DbaSchemaChangeHistory quoted object names" -Tag IntegrationTests {
    BeforeAll {
        $nativeQuoteServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeQuoteSuffix = [Guid]::NewGuid().ToString("N")
        $nativeQuoteDatabaseName = "native_quote_" + $nativeQuoteSuffix
        # A single quote in the name ends the source's unescaped string literal.
        $nativeQuoteTableName = "nat'quote_" + $nativeQuoteSuffix
        $nativeQuoteCreated = $false
        $nativeQuoteFixture = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeQuoteServer, $nativeQuoteDatabaseName
        $nativeQuoteFixture.Create()
        $nativeQuoteCreated = $true
        $nativeQuoteFixture.ExecuteNonQuery("CREATE TABLE [dbo].[$nativeQuoteTableName] ([Id] int);")
    }

    AfterAll {
        if ($nativeQuoteCreated) {
            $splatRemoveNativeQuoteDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $nativeQuoteDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeQuoteDatabase
        }
    }

    It "returns the trace row of an object whose name contains a quote and treats a quoted Object value as data" {
        $nativeQuoteErrors = @()
        $splatNativeQuoteRead = @{
            SqlInstance     = $nativeQuoteServer
            Database        = $nativeQuoteDatabaseName
            Object          = $nativeQuoteTableName
            EnableException = $true
            ErrorVariable   = "nativeQuoteErrors"
        }
        $nativeQuoteRows = @(Get-DbaSchemaChangeHistory @splatNativeQuoteRead)
        $nativeQuoteErrors.Count | Should -Be 0
        $nativeQuoteRows.Count | Should -BeGreaterThan 0
        foreach ($nativeQuoteRow in $nativeQuoteRows) {
            $nativeQuoteRow.DatabaseName | Should -BeExactly $nativeQuoteDatabaseName
            $nativeQuoteRow.Object | Should -BeExactly $nativeQuoteTableName
        }
        @($nativeQuoteRows | Where-Object DDLOperation -eq "Create").Count | Should -BeGreaterThan 0

        # Spliced into the source's text this value ends the IN list, matches every trace row and comments out the rest.
        $splatNativeQuoteRead.Object = "x') OR 1=1 --"
        @(Get-DbaSchemaChangeHistory @splatNativeQuoteRead).Count | Should -Be 0
        $nativeQuoteErrors.Count | Should -Be 0
    }
}

Describe "Native Get-DbaSchemaChangeHistory refuses Azure SQL Database" -Tag IntegrationTests {
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
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Get-DbaSchemaChangeHistory @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaSchemaChangeHistory -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Get-DbaSchemaChangeHistory over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginSuffix = [Guid]::NewGuid().ToString("N")
            $loginDbName = "native_schema_sqllogin_" + $loginSuffix
            $loginTableName = "native_schema_sqllogin_table_" + $loginSuffix
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[$loginTableName] ([Id] int);")
            # Independent of the command: the instance's default trace, and the CREATE TABLE event in its file.
            # SQL Trace writes its file in buffers, so on an idle instance the event can appear only after a
            # flush; wait for it (bounded) before asking the command for it.
            $loginTracePath = $loginServer.ConnectionContext.ExecuteScalar("SELECT path FROM sys.traces WHERE is_default = 1")
            $loginTraceEvents = 0
            if ($loginTracePath -and $loginTracePath -isnot [DBNull]) {
                $loginEventQuery = "SELECT COUNT(*) AS events FROM sys.fn_trace_gettable(N'" + ([string]$loginTracePath).Replace("'", "''") + "', DEFAULT) WHERE ObjectName = N'$loginTableName' AND DatabaseID = DB_ID() AND EventSubClass = 0 AND EventClass = 46"
                for ($loginAttempt = 0; $loginAttempt -lt 30; $loginAttempt++) {
                    $loginTraceEvents = [int]$loginDatabase.ExecuteWithResults($loginEventQuery).Tables[0].Rows[0].events
                    if ($loginTraceEvents -gt 0) { break }
                    Start-Sleep -Seconds 1
                }
            }
        }
        AfterAll {
            if ($loginDbName) {
                $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Confirm:$false
            }
        }

        It "works with -SqlCredential" {
            $loginTracePath | Should -Not -BeNullOrEmpty -Because "the instance must run the default trace the command reads"
            $loginTraceEvents | Should -BeGreaterThan 0 -Because "the default trace file must show the CREATE TABLE within 30 seconds"
            $loginRows = @(Get-DbaSchemaChangeHistory -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -Object $loginTableName -EnableException)
            $loginRows.Count | Should -BeGreaterThan 0
            foreach ($loginRow in $loginRows) {
                $loginRow.DatabaseName | Should -BeExactly $loginDbName
                $loginRow.Object | Should -BeExactly $loginTableName
            }
            @($loginRows | Where-Object DDLOperation -eq "Create").Count | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginResult = @(Get-DbaSchemaChangeHistory -SqlInstance $loginInstance -Database $loginDbName -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        # The pinned function connects with Connect-DbaInstance in try and calls Stop-Function on its failure
        # (pinned public/Get-DbaSchemaChangeHistory.ps1:108-112), so -EnableException throws.
        It "fails cleanly without the credential: -EnableException throws a connection error" {
            { Get-DbaSchemaChangeHistory -SqlInstance $loginInstance -Database $loginDbName -EnableException } | Should -Throw
        }
    }
}
