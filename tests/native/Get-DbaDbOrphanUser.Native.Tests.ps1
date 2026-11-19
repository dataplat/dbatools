#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbOrphanUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native orphan user behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeOrphanCreated = @()
        $nativeOrphanLogins = @()
        $nativeOrphanServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeOrphanSuffix = [Guid]::NewGuid().ToString("N")
        $nativeOrphanDatabaseName = "native_orphan_" + $nativeOrphanSuffix
        $nativeOrphanCleanName = "native_orphan_clean_" + $nativeOrphanSuffix
        $nativeOrphanDropped = "native_orphan_dropped_" + $nativeOrphanSuffix
        $nativeOrphanKept = "native_orphan_kept_" + $nativeOrphanSuffix
        $nativeOrphanNoLogin = "native_orphan_nologin_" + $nativeOrphanSuffix
        $nativeOrphanPassword = "Np1!" + [Guid]::NewGuid().ToString("N")
        foreach ($nativeOrphanName in $nativeOrphanDatabaseName, $nativeOrphanCleanName) {
            $nativeOrphanNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeOrphanServer, $nativeOrphanName
            $nativeOrphanNew.Create()
            $nativeOrphanCreated += $nativeOrphanName
        }
        foreach ($nativeOrphanLogin in $nativeOrphanDropped, $nativeOrphanKept) {
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeOrphanLogin] WITH PASSWORD = N'$nativeOrphanPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            $nativeOrphanLogins += $nativeOrphanLogin
        }
        $nativeOrphanDatabase = $nativeOrphanServer.Databases[$nativeOrphanDatabaseName]
        $nativeOrphanDatabase.ExecuteNonQuery("CREATE USER [$nativeOrphanDropped] FROM LOGIN [$nativeOrphanDropped]; CREATE USER [$nativeOrphanKept] FROM LOGIN [$nativeOrphanKept]; CREATE USER [$nativeOrphanNoLogin] WITHOUT LOGIN;")
        $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$nativeOrphanDropped];")
        $nativeOrphanServer.Logins.Refresh()
        $nativeOrphanDatabase.Users.Refresh()
    }

    AfterAll {
        if ($nativeOrphanCreated) {
            $splatRemoveNativeOrphanDatabase = @{
                SqlInstance     = $nativeOrphanServer
                Database        = $nativeOrphanCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeOrphanDatabase
        }
        foreach ($nativeOrphanLogin in $nativeOrphanLogins) {
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$nativeOrphanLogin') IS NOT NULL DROP LOGIN [$nativeOrphanLogin];")
        }
    }

    It "reports only the login-less SQL user with exact output shape across repeated pipeline records" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeOrphanRead = @{
            Database        = $nativeOrphanDatabaseName, $nativeOrphanCleanName
            EnableException = $true
            Verbose         = $true
        }
        $nativeOrphanMessages = @(@($nativeOrphanServer, $nativeOrphanServer) | Get-DbaDbOrphanUser @splatNativeOrphanRead 4>&1)
        $nativeOrphanRows = @($nativeOrphanMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
        $nativeOrphanRows.Count | Should -Be 2
        foreach ($nativeOrphanRow in $nativeOrphanRows) {
            ($nativeOrphanRow.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,DatabaseName,User,SmoUser"
            ($nativeOrphanRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,DatabaseName,User"
            $nativeOrphanRow.ComputerName | Should -BeExactly $nativeOrphanServer.ComputerName
            $nativeOrphanRow.InstanceName | Should -BeExactly $nativeOrphanServer.ServiceName
            $nativeOrphanRow.SqlInstance | Should -BeExactly $nativeOrphanServer.DomainInstanceName
            $nativeOrphanRow.DatabaseName | Should -BeExactly $nativeOrphanDatabaseName
            $nativeOrphanRow.User | Should -BeExactly $nativeOrphanDropped
            $nativeOrphanRow.SmoUser | Should -BeOfType Microsoft.SqlServer.Management.Smo.User
            $nativeOrphanRow.SmoUser.Name | Should -BeExactly $nativeOrphanDropped
        }
        @($nativeOrphanMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No orphan users found on database '``[$nativeOrphanCleanName``]'.*" }).Count | Should -Be 2
        @($nativeOrphanMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Orphan users found*" -and $PSItem.Message -notlike "*No orphan*" }).Count | Should -Be 2
    }

    It "uses literal case-insensitive database selection with exclusion taking precedence" {
        $splatNativeOrphanFilter = @{
            SqlInstance     = $nativeOrphanServer
            Database        = $nativeOrphanDatabaseName.ToUpperInvariant()
            EnableException = $true
        }
        (@(Get-DbaDbOrphanUser @splatNativeOrphanFilter).User -join ",") | Should -BeExactly $nativeOrphanDropped
        @(Get-DbaDbOrphanUser @splatNativeOrphanFilter -ExcludeDatabase $nativeOrphanDatabaseName).Count | Should -Be 0
        $splatNativeOrphanFilter.Database = "native_orphan_absent_" + $nativeOrphanSuffix
        $nativeOrphanNone = @(Get-DbaDbOrphanUser @splatNativeOrphanFilter -Verbose 4>&1)
        @($nativeOrphanNone | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        @($nativeOrphanNone | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*There are no databases to analyse.*" }).Count | Should -Be 1
    }

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :24 documents wildcards for -Database; :103 filters with literal -In, so the documented
            # form never took effect. Help :27-28 documents no wildcards for -ExcludeDatabase, which stays literal.
            $nativeOrphanWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanWildcardNames = @(
                "${nativeOrphanWildcardPrefix}_a"
                "${nativeOrphanWildcardPrefix}_b"
                "${nativeOrphanWildcardPrefix}_[a]"
            )
            $nativeOrphanWildcardLogin = "native_wc_login_" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanWildcardPassword = "Np1!" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanWildcardCreated = New-Object System.Collections.Generic.List[string]
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeOrphanWildcardLogin] WITH PASSWORD = N'$nativeOrphanWildcardPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            foreach ($nativeOrphanWildcardName in $nativeOrphanWildcardNames) {
                $nativeOrphanWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeOrphanServer, $nativeOrphanWildcardName
                $nativeOrphanWildcardDatabase.Create()
                $nativeOrphanWildcardCreated.Add($nativeOrphanWildcardName)
                $nativeOrphanWildcardDatabase.ExecuteNonQuery("CREATE USER [$nativeOrphanWildcardLogin] FROM LOGIN [$nativeOrphanWildcardLogin];")
            }
            # Dropping the login leaves each SQL-login user with its 16-byte SID and an empty Login: orphaned.
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$nativeOrphanWildcardLogin];")
            $nativeOrphanServer.Logins.Refresh()
            foreach ($nativeOrphanWildcardName in $nativeOrphanWildcardNames) {
                $nativeOrphanServer.Databases[$nativeOrphanWildcardName].Users.Refresh()
            }
        }

        AfterAll {
            $nativeOrphanServer.Databases.Refresh()
            foreach ($nativeOrphanWildcardName in $nativeOrphanWildcardCreated) {
                if ($nativeOrphanServer.Databases[$nativeOrphanWildcardName]) {
                    $nativeOrphanServer.KillDatabase($nativeOrphanWildcardName)
                }
            }
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$nativeOrphanWildcardLogin') IS NOT NULL DROP LOGIN [$nativeOrphanWildcardLogin];")
        }

        It "selects databases by a documented wildcard pattern" {
            $splatNativeOrphanWildcard = @{
                SqlInstance     = $nativeOrphanServer
                Database        = "${nativeOrphanWildcardPrefix}_*"
                EnableException = $true
            }
            $nativeOrphanWildcardRows = @(Get-DbaDbOrphanUser @splatNativeOrphanWildcard)
            (($nativeOrphanWildcardRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanWildcardNames | Sort-Object) -join ",")
            @($nativeOrphanWildcardRows | Where-Object User -ne $nativeOrphanWildcardLogin).Count | Should -Be 0
            $splatNativeOrphanWildcard.Database = "${nativeOrphanWildcardPrefix}_?"
            $nativeOrphanWildcardRows = @(Get-DbaDbOrphanUser @splatNativeOrphanWildcard)
            (($nativeOrphanWildcardRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "keeps bracket-only, invalid and undocumented exclusion values literal" {
            $splatNativeOrphanLiteral = @{
                SqlInstance     = $nativeOrphanServer
                Database        = $nativeOrphanWildcardNames[2]
                EnableException = $true
            }
            (@(Get-DbaDbOrphanUser @splatNativeOrphanLiteral).DatabaseName -join ",") | Should -BeExactly $nativeOrphanWildcardNames[2]
            $splatNativeOrphanLiteral.Database = "${nativeOrphanWildcardPrefix}_[*"
            @(Get-DbaDbOrphanUser @splatNativeOrphanLiteral).Count | Should -Be 0
            $splatNativeOrphanLiteral.Database = $nativeOrphanWildcardNames
            $splatNativeOrphanLiteral.ExcludeDatabase = "${nativeOrphanWildcardPrefix}_?"
            ((@(Get-DbaDbOrphanUser @splatNativeOrphanLiteral).DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanWildcardNames | Sort-Object) -join ",")
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :24 documents -Database wildcards; pinned Remove-DbaDbOrphanUser.ps1:185 and Repair-DbaDbOrphanUser.ps1:159 pass a real $db.Name): a value equal to a real database name stays
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
            $nativeOrphanRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanRealNameNames = @("${nativeOrphanRealNamePrefix}_*", "${nativeOrphanRealNamePrefix}_?", "${nativeOrphanRealNamePrefix}_x")
            $nativeOrphanRealNameCreated = New-Object System.Collections.Generic.List[string]
            $nativeOrphanRealNameLogin = "native_wc_login_" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanRealNamePassword = "Np1!" + [Guid]::NewGuid().ToString("N")
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeOrphanRealNameLogin] WITH PASSWORD = N'$nativeOrphanRealNamePassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            foreach ($nativeOrphanRealNameIndex in 0, 1, 2) {
                $nativeOrphanRealNameName = $nativeOrphanRealNameNames[$nativeOrphanRealNameIndex]
                $nativeOrphanRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeOrphanServer -Name $nativeOrphanRealNameName -FileStem ("${nativeOrphanRealNamePrefix}_file" + $nativeOrphanRealNameIndex)
                $nativeOrphanRealNameCreated.Add($nativeOrphanRealNameName)
                $nativeOrphanRealNameDatabase.ExecuteNonQuery("CREATE USER [$nativeOrphanRealNameLogin] FROM LOGIN [$nativeOrphanRealNameLogin];")
            }
            # Dropping the login leaves each SQL-login user with its 16-byte SID and an empty Login: orphaned.
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$nativeOrphanRealNameLogin];")
            $nativeOrphanServer.Logins.Refresh()
            foreach ($nativeOrphanRealNameName in $nativeOrphanRealNameNames) {
                $nativeOrphanServer.Databases[$nativeOrphanRealNameName].Users.Refresh()
            }
        }

        AfterAll {
            $nativeOrphanServer.Databases.Refresh()
            foreach ($nativeOrphanRealNameName in $nativeOrphanRealNameCreated) {
                if ($nativeOrphanServer.Databases[$nativeOrphanRealNameName]) {
                    $nativeOrphanServer.KillDatabase($nativeOrphanRealNameName)
                }
            }
            $nativeOrphanServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$nativeOrphanRealNameLogin') IS NOT NULL DROP LOGIN [$nativeOrphanRealNameLogin];")
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeOrphanRealNameExact = @{
                SqlInstance     = $nativeOrphanServer
                Database        = $nativeOrphanRealNameNames[0]
                EnableException = $true
            }
            $nativeOrphanRealNameRows = @(Get-DbaDbOrphanUser @splatNativeOrphanRealNameExact)
            (($nativeOrphanRealNameRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly $nativeOrphanRealNameNames[0]
            $splatNativeOrphanRealNameExact.Database = $nativeOrphanRealNameNames[1].ToUpperInvariant()
            $nativeOrphanRealNameRows = @(Get-DbaDbOrphanUser @splatNativeOrphanRealNameExact)
            (($nativeOrphanRealNameRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly $nativeOrphanRealNameNames[1]
            $splatNativeOrphanRealNameExact.Database = $nativeOrphanRealNameNames[0, 1]
            $nativeOrphanRealNameRows = @(Get-DbaDbOrphanUser @splatNativeOrphanRealNameExact)
            (($nativeOrphanRealNameRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeOrphanRealNamePattern = @{
                SqlInstance     = $nativeOrphanServer
                Database        = "${nativeOrphanRealNamePrefix}*"
                EnableException = $true
            }
            $nativeOrphanRealNameRows = @(Get-DbaDbOrphanUser @splatNativeOrphanRealNamePattern)
            (($nativeOrphanRealNameRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanRealNameNames | Sort-Object) -join ",")
            # -ExcludeDatabase documents no wildcards, so a real name in it stays literal.
            $splatNativeOrphanRealNamePattern.ExcludeDatabase = $nativeOrphanRealNameNames[1]
            $nativeOrphanRealNameRows = @(Get-DbaDbOrphanUser @splatNativeOrphanRealNamePattern)
            (($nativeOrphanRealNameRows.DatabaseName | Sort-Object) -join ",") | Should -BeExactly (($nativeOrphanRealNameNames[0, 2] | Sort-Object) -join ",")
        }
    }

    It "continues after connection failure unless EnableException terminates while retaining earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeOrphanSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeOrphanListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeOrphanListener.Start()
            $nativeOrphanFailedInstance = "127.0.0.1," + $nativeOrphanListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeOrphanWarnings = @()
            $nativeOrphanPreviousErrors = @($global:Error)
            $splatNativeOrphanFailure = @{
                Database        = $nativeOrphanDatabaseName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeOrphanWarnings"
            }
            $nativeOrphanContinued = @(@($nativeOrphanServer, $nativeOrphanFailedInstance, $nativeOrphanServer) | Get-DbaDbOrphanUser @splatNativeOrphanFailure)
            ($nativeOrphanContinued.User -join ",") | Should -BeExactly "$nativeOrphanDropped,$nativeOrphanDropped"
            ($nativeOrphanWarnings -join " ") | Should -BeLike "*Failure*"
            $nativeOrphanConnectionError = $global:Error | Where-Object {
                $nativeOrphanPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbOrphanUser*"
            } | Select-Object -First 1
            $nativeOrphanConnectionError | Should -Not -BeNullOrEmpty
            $nativeOrphanConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"

            $nativeOrphanEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeOrphanCaught = $null
            $splatNativeOrphanFailure.EnableException = $true
            try {
                @($nativeOrphanServer, $nativeOrphanFailedInstance, $nativeOrphanServer) |
                    Get-DbaDbOrphanUser @splatNativeOrphanFailure |
                    ForEach-Object { $nativeOrphanEarlier.Add($PSItem) }
            } catch {
                $nativeOrphanCaught = $PSItem
            }
            $nativeOrphanEarlier.Count | Should -Be 1
            $nativeOrphanEarlier[0].User | Should -BeExactly $nativeOrphanDropped
            $nativeOrphanCaught | Should -Not -BeNullOrEmpty
            $nativeOrphanCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeOrphanCaught.TargetObject | Should -Be $nativeOrphanFailedInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeOrphanSavedTimeout
            $nativeOrphanListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbOrphanUser numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeOrphanNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeOrphanNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeOrphanNumberNames = @("0$nativeOrphanNumber", "$nativeOrphanNumber")
        $nativeOrphanNumberLogin = "native_orphan_number_" + [Guid]::NewGuid().ToString("N")
        $nativeOrphanNumberPassword = "Np1!" + [Guid]::NewGuid().ToString("N")
        $nativeOrphanNumberCreated = @()
        $nativeOrphanNumberServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeOrphanNumberLogin] WITH PASSWORD = N'$nativeOrphanNumberPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
        foreach ($nativeOrphanNumberName in $nativeOrphanNumberNames) {
            $nativeOrphanNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeOrphanNumberServer, $nativeOrphanNumberName
            $nativeOrphanNumberDatabase.Create()
            $nativeOrphanNumberCreated += $nativeOrphanNumberName
            # A SQL-login user whose login is then dropped keeps its 16-byte SID with an empty Login: orphaned in the pinned command's sense.
            $nativeOrphanNumberDatabase.ExecuteNonQuery("CREATE USER [$nativeOrphanNumberLogin] FROM LOGIN [$nativeOrphanNumberLogin];")
        }
        $nativeOrphanNumberServer.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$nativeOrphanNumberLogin];")
        $nativeOrphanNumberServer.Logins.Refresh()
        foreach ($nativeOrphanNumberName in $nativeOrphanNumberNames) {
            $nativeOrphanNumberServer.Databases[$nativeOrphanNumberName].Users.Refresh()
        }
    }

    AfterAll {
        if ($nativeOrphanNumberCreated.Count -gt 0) {
            $splatRemoveNativeOrphanNumberDatabase = @{
                SqlInstance     = $nativeOrphanNumberServer
                Database        = $nativeOrphanNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeOrphanNumberDatabase
        }
        $nativeOrphanNumberServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$nativeOrphanNumberLogin') IS NOT NULL DROP LOGIN [$nativeOrphanNumberLogin];")
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeOrphanNumberInclude = @{
            SqlInstance     = $nativeOrphanNumberServer
            Database        = [int]$nativeOrphanNumber
            EnableException = $true
        }
        $nativeOrphanNumberIncluded = @(Get-DbaDbOrphanUser @splatNativeOrphanNumberInclude)
        (($nativeOrphanNumberIncluded.DatabaseName | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeOrphanNumberNames | Sort-Object) -join ",")
        @($nativeOrphanNumberIncluded | Where-Object User -ne $nativeOrphanNumberLogin).Count | Should -Be 0

        $splatNativeOrphanNumberExclude = @{
            SqlInstance     = $nativeOrphanNumberServer
            Database        = $nativeOrphanNumberNames
            ExcludeDatabase = [int]$nativeOrphanNumber
            EnableException = $true
        }
        @(Get-DbaDbOrphanUser @splatNativeOrphanNumberExclude).Count | Should -Be 0
    }
}

# NativeChecklist: azure-sqldb N/A -- orphan detection on Azure SQL Database needs the login SIDs read over a separate connection to the logical server's master and compared with the database's users, because sys.server_principals is not available there (https://learn.microsoft.com/sql/sql-server/failover-clusters/troubleshoot-orphaned-users-sql-server, "For Azure SQL Database"); the pinned function reads $server.Logins and User.Login on the one connection (public/Get-DbaDbOrphanUser.ps1:121-132), which fails in a user database, so supporting Azure means rewriting the detection. The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Get-DbaDbOrphanUser refuses Azure SQL Database" -Tag IntegrationTests {
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
            Database        = $TestConfig.AzureSqlDbName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Get-DbaDbOrphanUser @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaDbOrphanUser -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Get-DbaDbOrphanUser over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginSuffix = [Guid]::NewGuid().ToString("N")
            $loginDbName = "native_orphan_sqllogin_" + $loginSuffix
            $loginOrphanName = "native_orphan_sqllogin_user_" + $loginSuffix
            $loginPassword = "Np1!" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$loginOrphanName] WITH PASSWORD = N'$loginPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            $loginDatabase.ExecuteNonQuery("CREATE USER [$loginOrphanName] FROM LOGIN [$loginOrphanName];")
            $loginServer.ConnectionContext.ExecuteNonQuery("DROP LOGIN [$loginOrphanName];")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
                $loginServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$loginOrphanName') IS NOT NULL DROP LOGIN [$loginOrphanName];")
            }
        }

        It "works with -SqlCredential" {
            $splatLoginOrphan = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbOrphanUser @splatLoginOrphan)
            ($loginRows.User -join ",") | Should -BeExactly $loginOrphanName
            $loginRows[0].DatabaseName | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbOrphanUser @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbOrphanUser -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
