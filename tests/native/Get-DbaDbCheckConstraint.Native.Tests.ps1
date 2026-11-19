#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbCheckConstraint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native check constraint behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeCheckCreated = $false
        $nativeCheckServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeCheckDatabaseName = "native_check_" + [Guid]::NewGuid().ToString("N")
        $nativeCheckDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeCheckServer, $nativeCheckDatabaseName
        $nativeCheckDatabase.Create()
        $nativeCheckCreated = $true
        $nativeCheckDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_checked] ([value] int CONSTRAINT [native_check_positive] CHECK ([value] > 0)); CREATE TABLE [dbo].[native_without_check] ([value] int);")
        $nativeCheckDatabase.Tables.Refresh()
        $nativeCheckExpected = $nativeCheckDatabase.Tables["native_checked", "dbo"].Checks["native_check_positive"]
        $nativeCheckDisplay = "ComputerName,InstanceName,SqlInstance,Database,Parent,ID,CreateDate,DateLastModified,Name,IsEnabled,IsChecked,NotForReplication,Text,State"
    }

    AfterAll {
        if ($nativeCheckCreated) {
            $splatRemoveNativeCheckDatabase = @{
                SqlInstance     = $nativeCheckServer
                Database        = $nativeCheckDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeCheckDatabase
        }
    }

    It "preserves typed constraints, database identity and display metadata across repeated pipeline records" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeCheckRead = @{
            Database           = $nativeCheckDatabaseName
            ExcludeSystemTable = $true
            EnableException    = $true
            Verbose            = $true
        }
        $nativeCheckMessages = @(@($nativeCheckServer, $nativeCheckServer) | Get-DbaDbCheckConstraint @splatNativeCheckRead 4>&1)
        $nativeCheckRows = @($nativeCheckMessages | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.Check] })
        $nativeCheckRows.Count | Should -Be 2
        foreach ($nativeCheckRow in $nativeCheckRows) {
            $nativeCheckRow.Name | Should -BeExactly "native_check_positive"
            $nativeCheckRow.Database | Should -BeExactly $nativeCheckDatabaseName
            $nativeCheckRow.DatabaseId | Should -Be $nativeCheckDatabase.ID
            $nativeCheckRow.Parent | Should -BeOfType Microsoft.SqlServer.Management.Smo.Table
            $nativeCheckRow.Parent.Name | Should -BeExactly "native_checked"
            $nativeCheckRow.ComputerName | Should -BeExactly $nativeCheckServer.ComputerName
            $nativeCheckRow.InstanceName | Should -BeExactly $nativeCheckServer.ServiceName
            $nativeCheckRow.SqlInstance | Should -BeExactly $nativeCheckServer.DomainInstanceName
            $nativeCheckRow.Text | Should -BeExactly $nativeCheckExpected.Text
            $nativeCheckRow.IsEnabled | Should -Be $true
            $nativeCheckRow.IsChecked | Should -Be $true
            ($nativeCheckRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeCheckDisplay
            @($nativeCheckRow.PSObject.Properties | Where-Object Name -eq "DatabaseId").Count | Should -Be 1
        }
        @($nativeCheckMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Checks exist in *native_without_check*" }).Count | Should -Be 2
    }

    It "uses literal case-insensitive database selection with exclusion taking precedence" -Tag "NativeChecklist:switch-false" {
        $splatNativeCheckFilter = @{
            SqlInstance        = $nativeCheckServer
            Database           = $nativeCheckDatabaseName.ToUpperInvariant()
            ExcludeSystemTable = $false
            EnableException    = $true
        }
        $nativeCheckIncluded = @(Get-DbaDbCheckConstraint @splatNativeCheckFilter)
        $nativeCheckIncluded.Count | Should -Be 1
        $nativeCheckIncluded[0].Name | Should -BeExactly "native_check_positive"
        $splatNativeCheckFilter.ExcludeDatabase = $nativeCheckDatabaseName.ToUpperInvariant()
        @(Get-DbaDbCheckConstraint @splatNativeCheckFilter).Count | Should -Be 0
    }

    Context "Documented wildcard database selection and explicit false switches" {
        BeforeAll {
            # Pinned help :20 documents wildcards for -Database; :124 filters with literal -In, so the
            # documented form never took effect. Help :24 documents no wildcards for -ExcludeDatabase.
            # Pinned :137 uses Test-Bound, so -ExcludeSystemTable:$false still excluded system tables.
            $nativeCheckWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeCheckWildcardNames = @(
                "${nativeCheckWildcardPrefix}_a"
                "${nativeCheckWildcardPrefix}_b"
                "${nativeCheckWildcardPrefix}_[a]"
            )
            $nativeCheckWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeCheckWildcardName in $nativeCheckWildcardNames) {
                $nativeCheckWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeCheckServer, $nativeCheckWildcardName
                $nativeCheckWildcardDatabase.Create()
                $nativeCheckWildcardCreated.Add($nativeCheckWildcardName)
                $nativeCheckWildcardDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_checked] ([value] int CONSTRAINT [native_wc_positive] CHECK ([value] > 0));")
            }
            $nativeCheckSystemDatabase = $nativeCheckServer.Databases[$nativeCheckWildcardNames[0]]
            $nativeCheckSystemDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_system_checked] ([value] int CONSTRAINT [native_wc_system_positive] CHECK ([value] > 0)); EXEC sys.sp_addextendedproperty @name = N'microsoft_database_tools_support', @value = 1, @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'native_wc_system_checked';")
            $nativeCheckSystemDatabase.Tables.Refresh()
            if (-not $nativeCheckSystemDatabase.Tables["native_wc_system_checked", "dbo"].IsSystemObject) {
                throw "The system-table fixture is not reported as a system object by SMO"
            }
        }

        AfterAll {
            $nativeCheckServer.Databases.Refresh()
            foreach ($nativeCheckWildcardName in $nativeCheckWildcardCreated) {
                if ($nativeCheckServer.Databases[$nativeCheckWildcardName]) {
                    $nativeCheckServer.KillDatabase($nativeCheckWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatNativeCheckWildcard = @{
                SqlInstance     = $nativeCheckServer
                Database        = "${nativeCheckWildcardPrefix}_*"
                EnableException = $true
            }
            $nativeCheckWildcardRows = @(Get-DbaDbCheckConstraint @splatNativeCheckWildcard)
            (($nativeCheckWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckWildcardNames | Sort-Object) -join ",")
            $splatNativeCheckWildcard.Database = "${nativeCheckWildcardPrefix}_?"
            $nativeCheckWildcardRows = @(Get-DbaDbCheckConstraint @splatNativeCheckWildcard)
            (($nativeCheckWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "keeps bracket-only, invalid and undocumented exclusion values literal" {
            $splatNativeCheckLiteral = @{
                SqlInstance     = $nativeCheckServer
                Database        = $nativeCheckWildcardNames[2]
                EnableException = $true
            }
            $nativeCheckLiteralRows = @(Get-DbaDbCheckConstraint @splatNativeCheckLiteral)
            (($nativeCheckLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeCheckWildcardNames[2]
            $splatNativeCheckLiteral.Database = "${nativeCheckWildcardPrefix}_[*"
            @(Get-DbaDbCheckConstraint @splatNativeCheckLiteral).Count | Should -Be 0
            $splatNativeCheckLiteral.Database = $nativeCheckWildcardNames
            $splatNativeCheckLiteral.ExcludeDatabase = "${nativeCheckWildcardPrefix}_?"
            $nativeCheckLiteralRows = @(Get-DbaDbCheckConstraint @splatNativeCheckLiteral)
            (($nativeCheckLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckWildcardNames | Sort-Object) -join ",")
        }

        It "includes system tables when -ExcludeSystemTable is explicitly false" -Tag "NativeChecklist:switch-false" {
            $splatNativeCheckSystem = @{
                SqlInstance     = $nativeCheckServer
                Database        = $nativeCheckWildcardNames[0]
                EnableException = $true
            }
            $nativeCheckBoth = "native_wc_positive,native_wc_system_positive"
            ((@(Get-DbaDbCheckConstraint @splatNativeCheckSystem).Name | Sort-Object) -join ",") | Should -BeExactly $nativeCheckBoth
            ((@(Get-DbaDbCheckConstraint @splatNativeCheckSystem -ExcludeSystemTable:$false).Name | Sort-Object) -join ",") | Should -BeExactly $nativeCheckBoth
            ((@(Get-DbaDbCheckConstraint @splatNativeCheckSystem -ExcludeSystemTable).Name | Sort-Object) -join ",") | Should -BeExactly "native_wc_positive"
        }
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
            $nativeCheckRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeCheckRealNameNames = @("${nativeCheckRealNamePrefix}_*", "${nativeCheckRealNamePrefix}_?", "${nativeCheckRealNamePrefix}_x")
            $nativeCheckRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeCheckRealNameIndex in 0, 1, 2) {
                $nativeCheckRealNameName = $nativeCheckRealNameNames[$nativeCheckRealNameIndex]
                $nativeCheckRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeCheckServer -Name $nativeCheckRealNameName -FileStem ("${nativeCheckRealNamePrefix}_file" + $nativeCheckRealNameIndex)
                $nativeCheckRealNameCreated.Add($nativeCheckRealNameName)
                $nativeCheckRealNameDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_wc_checked] ([value] int CONSTRAINT [native_wc_positive] CHECK ([value] > 0));")
            }
        }

        AfterAll {
            $nativeCheckServer.Databases.Refresh()
            foreach ($nativeCheckRealNameName in $nativeCheckRealNameCreated) {
                if ($nativeCheckServer.Databases[$nativeCheckRealNameName]) {
                    $nativeCheckServer.KillDatabase($nativeCheckRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeCheckRealNameExact = @{
                SqlInstance     = $nativeCheckServer
                Database        = $nativeCheckRealNameNames[0]
                EnableException = $true
            }
            $nativeCheckRealNameRows = @(Get-DbaDbCheckConstraint @splatNativeCheckRealNameExact)
            (($nativeCheckRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeCheckRealNameNames[0]
            $splatNativeCheckRealNameExact.Database = $nativeCheckRealNameNames[1].ToUpperInvariant()
            $nativeCheckRealNameRows = @(Get-DbaDbCheckConstraint @splatNativeCheckRealNameExact)
            (($nativeCheckRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeCheckRealNameNames[1]
            $splatNativeCheckRealNameExact.Database = $nativeCheckRealNameNames[0, 1]
            $nativeCheckRealNameRows = @(Get-DbaDbCheckConstraint @splatNativeCheckRealNameExact)
            (($nativeCheckRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeCheckRealNamePattern = @{
                SqlInstance     = $nativeCheckServer
                Database        = "${nativeCheckRealNamePrefix}*"
                EnableException = $true
            }
            $nativeCheckRealNameRows = @(Get-DbaDbCheckConstraint @splatNativeCheckRealNamePattern)
            (($nativeCheckRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckRealNameNames | Sort-Object) -join ",")
        }
    }

    It "continues after connection failure unless EnableException terminates while retaining earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeCheckSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeCheckListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeCheckListener.Start()
            $nativeCheckFailedInstance = "127.0.0.1," + $nativeCheckListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeCheckWarnings = @()
            $splatNativeCheckFailure = @{
                Database           = $nativeCheckDatabaseName
                ExcludeSystemTable = $true
                EnableException    = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "nativeCheckWarnings"
            }
            $nativeCheckContinued = @(@($nativeCheckServer, $nativeCheckFailedInstance, $nativeCheckServer) | Get-DbaDbCheckConstraint @splatNativeCheckFailure)
            $nativeCheckContinued.Count | Should -Be 2
            @($nativeCheckContinued | Where-Object Name -ne "native_check_positive").Count | Should -Be 0
            ($nativeCheckWarnings -join " ") | Should -BeLike "*Failure*"

            $nativeCheckEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeCheckCaught = $null
            $splatNativeCheckFailure.EnableException = $true
            try {
                @($nativeCheckServer, $nativeCheckFailedInstance, $nativeCheckServer) |
                    Get-DbaDbCheckConstraint @splatNativeCheckFailure |
                    ForEach-Object { $nativeCheckEarlier.Add($PSItem) }
            } catch {
                $nativeCheckCaught = $PSItem
            }
            $nativeCheckEarlier.Count | Should -Be 1
            $nativeCheckEarlier[0].Name | Should -BeExactly "native_check_positive"
            $nativeCheckCaught | Should -Not -BeNullOrEmpty
            $nativeCheckCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeCheckCaught.TargetObject | Should -Be $nativeCheckFailedInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeCheckSavedTimeout
            $nativeCheckListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbCheckConstraint numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeCheckNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeCheckNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeCheckNumberNames = @("0$nativeCheckNumber", "$nativeCheckNumber")
        $nativeCheckNumberCreated = @()
        foreach ($nativeCheckNumberName in $nativeCheckNumberNames) {
            $nativeCheckNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeCheckNumberServer, $nativeCheckNumberName
            $nativeCheckNumberDatabase.Create()
            $nativeCheckNumberCreated += $nativeCheckNumberName
            $nativeCheckNumberDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_number_checked] ([value] int CONSTRAINT [native_number_positive] CHECK ([value] > 0));")
        }
    }

    AfterAll {
        if ($nativeCheckNumberCreated.Count -gt 0) {
            $splatRemoveNativeCheckNumberDatabase = @{
                SqlInstance     = $nativeCheckNumberServer
                Database        = $nativeCheckNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeCheckNumberDatabase
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeCheckNumberInclude = @{
            SqlInstance     = $nativeCheckNumberServer
            Database        = [int]$nativeCheckNumber
            EnableException = $true
        }
        $nativeCheckNumberIncluded = @(Get-DbaDbCheckConstraint @splatNativeCheckNumberInclude)
        (($nativeCheckNumberIncluded.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeCheckNumberNames | Sort-Object) -join ",")

        $splatNativeCheckNumberExclude = @{
            SqlInstance     = $nativeCheckNumberServer
            Database        = $nativeCheckNumberNames
            ExcludeDatabase = [int]$nativeCheckNumber
            EnableException = $true
        }
        @(Get-DbaDbCheckConstraint @splatNativeCheckNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbCheckConstraint on Azure SQL Database" -Tag IntegrationTests {
    It "reads a check constraint in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        # Six legs share the database: unique names and cleanup.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azureTableName = "native_check_azure_$azureSuffix"
        $azureCheckName = "native_check_azure_ck_$azureSuffix"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTableName] ([value] int CONSTRAINT [$azureCheckName] CHECK ([value] > 0));")
            $splatAzureCheck = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbCheckConstraint @splatAzureCheck | Where-Object Name -eq $azureCheckName)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Check
            $azureRows[0].Parent.Name | Should -BeExactly $azureTableName
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureTableName]', N'U') IS NOT NULL DROP TABLE [dbo].[$azureTableName];")
        }
    }
}

Describe "Native Get-DbaDbCheckConstraint over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_check_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE [dbo].[native_login_checked] ([value] int CONSTRAINT [native_login_check] CHECK ([value] > 0));")
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
            $splatLoginCheck = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbCheckConstraint @splatLoginCheck)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "native_login_check"
            $loginRows[0].Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbCheckConstraint @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbCheckConstraint -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
