#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess.

Describe "Native database trigger behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeTriggerOwnedNames = New-Object "System.Collections.Generic.List[string]"
        $nativeTriggerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeTriggerDatabaseName = "native_trigger_" + [Guid]::NewGuid().ToString("N")
        $nativeTriggerDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeTriggerServer, $nativeTriggerDatabaseName
        $nativeTriggerDatabase.Create()
        $nativeTriggerOwnedNames.Add($nativeTriggerDatabaseName)
        $nativeTriggerName = "native_trigger_readback"
        $splatCreateNativeTrigger = @{
            SqlInstance     = $nativeTriggerServer
            Database        = $nativeTriggerDatabaseName
            Query           = "CREATE TRIGGER [$nativeTriggerName] ON DATABASE FOR CREATE_TABLE AS RETURN;"
            EnableException = $true
        }
        $null = Invoke-DbaQuery @splatCreateNativeTrigger
        $nativeTriggerFailures = @{}
        foreach ($nativeTriggerFailureMode in "continue", "terminate") {
            $nativeTriggerFailureName = "native_trigger_failure_" + [Guid]::NewGuid().ToString("N")
            $nativeTriggerFailureDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeTriggerServer, $nativeTriggerFailureName
            $nativeTriggerFailureDatabase.Create()
            $nativeTriggerOwnedNames.Add($nativeTriggerFailureName)
            # Drop independently so each untouched SMO trigger collection still queries an Existing database.
            $splatDropNativeTriggerFailure = @{
                SqlInstance     = $nativeTriggerServer
                Database        = "master"
                Query           = "DROP DATABASE [$nativeTriggerFailureName];"
                EnableException = $true
            }
            $null = Invoke-DbaQuery @splatDropNativeTriggerFailure
            $nativeTriggerFailures[$nativeTriggerFailureMode] = $nativeTriggerFailureDatabase
        }
        $nativeTriggerDisplay = "ComputerName,InstanceName,SqlInstance,Name,IsEnabled,DateLastModified"
    }

    AfterAll {
        if ($nativeTriggerServer) {
            $nativeTriggerServer.Databases.Refresh()
            foreach ($nativeTriggerOwnedName in $nativeTriggerOwnedNames) {
                if ($nativeTriggerServer.Databases[$nativeTriggerOwnedName]) {
                    $splatRemoveNativeTriggerDatabase = @{
                        SqlInstance     = $nativeTriggerServer
                        Database        = $nativeTriggerOwnedName
                        Confirm         = $false
                        EnableException = $true
                    }
                    Remove-DbaDatabase @splatRemoveNativeTriggerDatabase
                }
            }
        }
    }

    It "preserves typed triggers and instance display metadata on repeated input-object reads" {
        foreach ($nativeTriggerIteration in 1, 2) {
            $nativeTriggerRows = @($nativeTriggerDatabase | Get-DbaDbTrigger -EnableException)
            $nativeTriggerRows.Count | Should -Be 1
            $nativeTriggerRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger
            $nativeTriggerRows[0].Name | Should -BeExactly $nativeTriggerName
            $nativeTriggerRows[0].IsEnabled | Should -BeTrue
            $nativeTriggerRows[0].ComputerName | Should -BeExactly $nativeTriggerServer.ComputerName
            $nativeTriggerRows[0].InstanceName | Should -BeExactly $nativeTriggerServer.ServiceName
            $nativeTriggerRows[0].SqlInstance | Should -BeExactly $nativeTriggerServer.DomainInstanceName
            ($nativeTriggerRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeTriggerDisplay
            @($nativeTriggerRows[0].PSObject.Properties | Where-Object Name -eq "SqlInstance").Count | Should -Be 1
        }
    }

    It "appends each instance's databases once to an explicit input database" {
        $splatNativeTriggerCombined = @{
            SqlInstance     = @($nativeTriggerServer, $nativeTriggerServer)
            Database        = $nativeTriggerDatabaseName.ToUpperInvariant()
            InputObject     = $nativeTriggerDatabase
            EnableException = $true
        }
        # Upstream correction (wrong data): the pinned source gathers the whole -SqlInstance array once per
        # entry, so N instances return every trigger N times; each instance is now gathered once.
        $nativeTriggerCombinedRows = @(Get-DbaDbTrigger @splatNativeTriggerCombined)
        $nativeTriggerCombinedRows.Count | Should -Be 3
        @($nativeTriggerCombinedRows | Where-Object Name -ne $nativeTriggerName).Count | Should -Be 0
    }

    It "warns for a failed middle database and continues the input-object pipeline" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeTriggerWarnings = @()
        $nativeTriggerPriorErrors = @($global:Error)
        $splatNativeTriggerContinue = @{
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeTriggerWarnings"
        }
        $nativeTriggerContinuedRows = @(
            @($nativeTriggerDatabase, $nativeTriggerFailures["continue"], $nativeTriggerDatabase) |
                Get-DbaDbTrigger @splatNativeTriggerContinue
        )
        $nativeTriggerContinuedRows.Count | Should -Be 2
        $nativeTriggerContinuedRows[0].Name | Should -BeExactly $nativeTriggerName
        $nativeTriggerContinuedRows[1].Name | Should -BeExactly $nativeTriggerName
        ($nativeTriggerWarnings -join " ") | Should -BeLike "*Failure*"
        $nativeTriggerDatabaseError = $global:Error | Where-Object {
            $nativeTriggerPriorErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbTrigger*"
        } | Select-Object -First 1
        $nativeTriggerDatabaseError | Should -Not -BeNullOrEmpty
        # Stop-Function receives no -Target here.
        $nativeTriggerDatabaseError.TargetObject | Should -BeNullOrEmpty
        $nativeTriggerDatabaseError.Exception.InnerException | Should -Not -BeNullOrEmpty
    }

    It "retains earlier output when EnableException terminates the input-object pipeline" -Tag "NativeChecklist:enable-exception" {
        $nativeTriggerEarlierRows = New-Object "System.Collections.Generic.List[object]"
        $nativeTriggerCaught = $null
        try {
            @($nativeTriggerDatabase, $nativeTriggerFailures["terminate"], $nativeTriggerDatabase) |
                Get-DbaDbTrigger -EnableException |
                ForEach-Object { $nativeTriggerEarlierRows.Add($PSItem) }
        } catch {
            $nativeTriggerCaught = $PSItem
        }
        $nativeTriggerEarlierRows.Count | Should -Be 1
        $nativeTriggerEarlierRows[0].Name | Should -BeExactly $nativeTriggerName
        $nativeTriggerCaught | Should -Not -BeNullOrEmpty
        # Stop-Function -Continue still throws its own record under EnableException.
        $nativeTriggerCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbTrigger*"
        $nativeTriggerCaught.Exception.InnerException | Should -Not -BeNullOrEmpty
    }

    It "continues repeated instance discovery after a failed middle instance with either EnableException value" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeTriggerSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeTriggerListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeTriggerListener.Start()
            $nativeTriggerFailedInstance = "127.0.0.1," + $nativeTriggerListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            foreach ($nativeTriggerEnableException in $false, $true) {
                $nativeTriggerInstanceWarnings = @()
                $nativeTriggerInstancePriorErrors = @($global:Error)
                $splatNativeTriggerInstanceFailure = @{
                    SqlInstance     = @($nativeTriggerServer, $nativeTriggerFailedInstance, $nativeTriggerServer)
                    Database        = $nativeTriggerDatabaseName
                    EnableException = $nativeTriggerEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "nativeTriggerInstanceWarnings"
                }
                $nativeTriggerInstanceRows = @(Get-DbaDbTrigger @splatNativeTriggerInstanceFailure)
                # Each instance is gathered once (upstream correction), and EnableException is not forwarded.
                $nativeTriggerInstanceRows.Count | Should -Be 2
                @($nativeTriggerInstanceRows | Where-Object Name -ne $nativeTriggerName).Count | Should -Be 0
                ($nativeTriggerInstanceWarnings -join " ") | Should -BeLike "*Failure*"
                # The connection failure is reported by the source's nested Get-DbaDatabase call.
                $nativeTriggerConnectionErrors = @($global:Error | Where-Object {
                        $nativeTriggerInstancePriorErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
                    })
                $nativeTriggerConnectionErrors.Count | Should -Be 1
                $nativeTriggerConnectionErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
                $nativeTriggerConnectionErrors[0].TargetObject.GetType().FullName | Should -BeExactly "System.String"
                $nativeTriggerConnectionErrors[0].TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeTriggerFailedInstance).FullSmoName
            }
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeTriggerSavedTimeout
            $nativeTriggerListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbTrigger documented wildcard database selection" -Tag IntegrationTests {
    BeforeAll {
        # Pinned help :20 documents wildcards for -Database; :101 delegates to the exact-match Get-DbaDatabase,
        # so the documented form never took effect. Help :24-25 documents no wildcards for -ExcludeDatabase,
        # which stays literal.
        $nativeTriggerWildcardServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeTriggerWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
        $nativeTriggerWildcardNames = @(
            "${nativeTriggerWildcardPrefix}_a"
            "${nativeTriggerWildcardPrefix}_b"
            "${nativeTriggerWildcardPrefix}_[a]"
        )
        $nativeTriggerWildcardCreated = New-Object System.Collections.Generic.List[string]
        foreach ($nativeTriggerWildcardName in $nativeTriggerWildcardNames) {
            $nativeTriggerWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeTriggerWildcardServer, $nativeTriggerWildcardName
            $nativeTriggerWildcardDatabase.Create()
            $nativeTriggerWildcardCreated.Add($nativeTriggerWildcardName)
            $nativeTriggerWildcardDatabase.ExecuteNonQuery("CREATE TRIGGER [native_wc_trigger] ON DATABASE FOR CREATE_TABLE AS RETURN;")
        }
    }

    AfterAll {
        $nativeTriggerWildcardServer.Databases.Refresh()
        foreach ($nativeTriggerWildcardName in $nativeTriggerWildcardCreated) {
            if ($nativeTriggerWildcardServer.Databases[$nativeTriggerWildcardName]) {
                $nativeTriggerWildcardServer.KillDatabase($nativeTriggerWildcardName)
            }
        }
    }

    It "selects databases by a documented wildcard pattern" {
        $splatNativeTriggerWildcard = @{
            SqlInstance     = $nativeTriggerWildcardServer
            Database        = "${nativeTriggerWildcardPrefix}_*"
            EnableException = $true
        }
        $nativeTriggerWildcardRows = @(Get-DbaDbTrigger @splatNativeTriggerWildcard)
        @($nativeTriggerWildcardRows | Where-Object Name -ne "native_wc_trigger").Count | Should -Be 0
        (($nativeTriggerWildcardRows | ForEach-Object { $PSItem.Parent.Name } | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerWildcardNames | Sort-Object) -join ",")
        $splatNativeTriggerWildcard.Database = "${nativeTriggerWildcardPrefix}_?"
        $nativeTriggerWildcardRows = @(Get-DbaDbTrigger @splatNativeTriggerWildcard)
        (($nativeTriggerWildcardRows | ForEach-Object { $PSItem.Parent.Name } | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerWildcardNames[0, 1] | Sort-Object) -join ",")
    }

    It "keeps bracket-only, invalid and undocumented exclusion values literal" {
        $splatNativeTriggerLiteral = @{
            SqlInstance     = $nativeTriggerWildcardServer
            Database        = $nativeTriggerWildcardNames[2]
            EnableException = $true
        }
        ((@(Get-DbaDbTrigger @splatNativeTriggerLiteral) | ForEach-Object { $PSItem.Parent.Name }) -join ",") | Should -BeExactly $nativeTriggerWildcardNames[2]
        $splatNativeTriggerLiteral.Database = "${nativeTriggerWildcardPrefix}_[*"
        @(Get-DbaDbTrigger @splatNativeTriggerLiteral).Count | Should -Be 0
        $splatNativeTriggerLiteral.Database = $nativeTriggerWildcardNames
        $splatNativeTriggerLiteral.ExcludeDatabase = "${nativeTriggerWildcardPrefix}_?"
        ((@(Get-DbaDbTrigger @splatNativeTriggerLiteral) | ForEach-Object { $PSItem.Parent.Name } | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerWildcardNames | Sort-Object) -join ",")
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
            $nativeTriggerRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeTriggerRealNameNames = @("${nativeTriggerRealNamePrefix}_*", "${nativeTriggerRealNamePrefix}_?", "${nativeTriggerRealNamePrefix}_x")
            $nativeTriggerRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeTriggerRealNameIndex in 0, 1, 2) {
                $nativeTriggerRealNameName = $nativeTriggerRealNameNames[$nativeTriggerRealNameIndex]
                $nativeTriggerRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeTriggerWildcardServer -Name $nativeTriggerRealNameName -FileStem ("${nativeTriggerRealNamePrefix}_file" + $nativeTriggerRealNameIndex)
                $nativeTriggerRealNameCreated.Add($nativeTriggerRealNameName)
                $nativeTriggerRealNameDatabase.ExecuteNonQuery("CREATE TRIGGER [native_wc_trigger] ON DATABASE FOR CREATE_TABLE AS RETURN;")
            }
        }

        AfterAll {
            $nativeTriggerWildcardServer.Databases.Refresh()
            foreach ($nativeTriggerRealNameName in $nativeTriggerRealNameCreated) {
                if ($nativeTriggerWildcardServer.Databases[$nativeTriggerRealNameName]) {
                    $nativeTriggerWildcardServer.KillDatabase($nativeTriggerRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeTriggerRealNameExact = @{
                SqlInstance     = $nativeTriggerWildcardServer
                Database        = $nativeTriggerRealNameNames[0]
                EnableException = $true
            }
            $nativeTriggerRealNameRows = @(Get-DbaDbTrigger @splatNativeTriggerRealNameExact)
            ((($nativeTriggerRealNameRows | ForEach-Object { $PSItem.Parent.Name }) | Sort-Object) -join ",") | Should -BeExactly $nativeTriggerRealNameNames[0]
            $splatNativeTriggerRealNameExact.Database = $nativeTriggerRealNameNames[1].ToUpperInvariant()
            $nativeTriggerRealNameRows = @(Get-DbaDbTrigger @splatNativeTriggerRealNameExact)
            ((($nativeTriggerRealNameRows | ForEach-Object { $PSItem.Parent.Name }) | Sort-Object) -join ",") | Should -BeExactly $nativeTriggerRealNameNames[1]
            $splatNativeTriggerRealNameExact.Database = $nativeTriggerRealNameNames[0, 1]
            $nativeTriggerRealNameRows = @(Get-DbaDbTrigger @splatNativeTriggerRealNameExact)
            ((($nativeTriggerRealNameRows | ForEach-Object { $PSItem.Parent.Name }) | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeTriggerRealNamePattern = @{
                SqlInstance     = $nativeTriggerWildcardServer
                Database        = "${nativeTriggerRealNamePrefix}*"
                EnableException = $true
            }
            $nativeTriggerRealNameRows = @(Get-DbaDbTrigger @splatNativeTriggerRealNamePattern)
            ((($nativeTriggerRealNameRows | ForEach-Object { $PSItem.Parent.Name }) | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerRealNameNames | Sort-Object) -join ",")
            # -ExcludeDatabase documents no wildcards, so a real name in it stays literal.
            $splatNativeTriggerRealNamePattern.ExcludeDatabase = $nativeTriggerRealNameNames[1]
            $nativeTriggerRealNameRows = @(Get-DbaDbTrigger @splatNativeTriggerRealNamePattern)
            ((($nativeTriggerRealNameRows | ForEach-Object { $PSItem.Parent.Name }) | Sort-Object) -join ",") | Should -BeExactly (($nativeTriggerRealNameNames[0, 2] | Sort-Object) -join ",")
        }
    }
}

Describe "Native Get-DbaDbTrigger literal database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeTriggerNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeTriggerNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeTriggerNumberName = "0$nativeTriggerNumber"
        $nativeTriggerNumberFixture = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeTriggerNumberServer, $nativeTriggerNumberName
        $nativeTriggerNumberFixture.Create()
        $splatCreateNativeTriggerNumber = @{
            SqlInstance     = $nativeTriggerNumberServer
            Database        = $nativeTriggerNumberName
            Query           = "CREATE TRIGGER [native_trigger_number] ON DATABASE FOR CREATE_TABLE AS RETURN;"
            EnableException = $true
        }
        $null = Invoke-DbaQuery @splatCreateNativeTriggerNumber
    }

    AfterAll {
        # Drop() fails while the command's pooled connection still uses the database, which left the database and
        # its DDL trigger behind and broke the pinned -ExcludeDatabase Master assertion on later legs; KillDatabase
        # ends those connections first.
        $nativeTriggerNumberServer.Databases.Refresh()
        if ($nativeTriggerNumberServer.Databases[$nativeTriggerNumberName]) {
            $nativeTriggerNumberServer.KillDatabase($nativeTriggerNumberName)
        }
    }

    It "binds a numeric selection to Get-DbaDatabase's string filter, so 1 does not select 01" {
        $splatNativeTriggerNumber = @{
            SqlInstance     = $nativeTriggerNumberServer
            Database        = $nativeTriggerNumberName
            EnableException = $true
        }
        @(Get-DbaDbTrigger @splatNativeTriggerNumber).Name | Should -BeExactly "native_trigger_number"
        $splatNativeTriggerNumber.Database = [int]$nativeTriggerNumber
        @(Get-DbaDbTrigger @splatNativeTriggerNumber).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbTrigger on Azure SQL Database" -Tag IntegrationTests {
    It "reads a database DDL trigger in Azure SQL Database by -SqlInstance and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
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
        # Six legs share the database: a unique trigger name, an event no test fires, and cleanup.
        $azureTriggerName = "native_trigger_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TRIGGER [$azureTriggerName] ON DATABASE FOR CREATE_SYNONYM AS RETURN;")
            $splatAzureTrigger = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbTrigger @splatAzureTrigger | Where-Object Name -eq $azureTriggerName)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger
            $azureRows[0].IsEnabled | Should -BeTrue
            $azureRows[0].Parent.Name | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $azurePipedRows = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbTrigger -EnableException | Where-Object Name -eq $azureTriggerName)
            $azurePipedRows.Count | Should -Be 1
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_class = 0 AND name = N'$azureTriggerName') DROP TRIGGER [$azureTriggerName] ON DATABASE;")
        }
    }
}

Describe "Native Get-DbaDbTrigger over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_trigger_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TRIGGER [native_trigger_sqllogin] ON DATABASE FOR CREATE_SYNONYM AS RETURN;")
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
            $splatLoginTrigger = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbTrigger @splatLoginTrigger)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "native_trigger_sqllogin"
            $loginRows[0].Parent.Name | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested database gather, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbTrigger @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
