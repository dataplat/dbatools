#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbAssembly",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess; no WhatIf or Confirm parameters.
Describe "Native database assembly behavior" -Tag IntegrationTests {
    BeforeAll {
        $dbAssemblyServer = $null
        $dbAssemblySecondServer = $null
        $dbAssemblyListener = $null
        $splatDbAssemblyConnection = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $dbAssemblyServer = Connect-DbaInstance @splatDbAssemblyConnection
        $splatDbAssemblySecondConnection = @{
            SqlInstance         = $dbAssemblyServer
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $dbAssemblySecondServer = Connect-DbaInstance @splatDbAssemblySecondConnection
        if ([object]::ReferenceEquals($dbAssemblyServer, $dbAssemblySecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        $dbAssemblyDatabase = $dbAssemblyServer.Databases["master"]
        $dbAssemblyFixture = $dbAssemblyDatabase.Assemblies["Microsoft.SqlServer.Types"]
        if ($null -eq $dbAssemblyFixture) { throw "The pinned master assembly fixture is absent" }
        # Hold a non-SQL endpoint so the failing connection cannot reach another service.
        $dbAssemblyListener = New-Object Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Loopback), 0
        $dbAssemblyListener.Start()
        $dbAssemblyPort = $dbAssemblyListener.LocalEndpoint.Port
        $dbAssemblyBadInstance = "Data Source=tcp:127.0.0.1,$dbAssemblyPort;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    AfterAll {
        if ($dbAssemblyListener) { $dbAssemblyListener.Stop() }
        if ($dbAssemblySecondServer) { $dbAssemblySecondServer.ConnectionContext.Disconnect() }
        if ($dbAssemblyServer) { $dbAssemblyServer.ConnectionContext.Disconnect() }
    }

    It "replaces typed assembly metadata and aliases and preserves bound empty filters" {
        foreach ($dbAssemblyProperty in @("ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseId", "SecurityLevel")) {
            $splatDbAssemblyStaleProperty = @{
                InputObject = $dbAssemblyFixture
                MemberType  = "NoteProperty"
                Name        = $dbAssemblyProperty
                Value       = "stale"
                Force       = $true
            }
            Add-Member @splatDbAssemblyStaleProperty
        }
        $splatDbAssemblyMetadata = @{
            SqlInstance     = $dbAssemblyServer
            Database        = "MASTER"
            Name            = "microsoft.sqlserver.types"
            EnableException = $true
        }
        $dbAssemblyRows = @(Get-DbaDbAssembly @splatDbAssemblyMetadata)
        $dbAssemblyRows.Count | Should -Be 1
        $dbAssemblyRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.SqlAssembly
        $dbAssemblyRows[0].ComputerName | Should -BeExactly $dbAssemblyServer.ComputerName
        $dbAssemblyRows[0].InstanceName | Should -BeExactly $dbAssemblyServer.ServiceName
        $dbAssemblyRows[0].SqlInstance | Should -BeExactly $dbAssemblyServer.DomainInstanceName
        $dbAssemblyRows[0].Database | Should -BeExactly "master"
        $dbAssemblyRows[0].DatabaseId | Should -Be $dbAssemblyDatabase.ID
        $dbAssemblyRows[0].SecurityLevel | Should -Be $dbAssemblyRows[0].AssemblySecurityLevel
        $dbAssemblyRows[0].PSObject.Properties["SecurityLevel"].MemberType | Should -Be "AliasProperty"
        ($dbAssemblyRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,ID,Name,Owner,SecurityLevel,CreateDate,IsSystemObject,Version"
        $splatDbAssemblyMetadata.Name = "Microsoft.SqlServer.*"
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -Be 0
        $splatDbAssemblyMetadata.Name = @()
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -Be 0
        $splatDbAssemblyMetadata.Name = $null
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -Be 0
        $splatDbAssemblyMetadata.Remove("Name")
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -BeGreaterThan 0
        $splatDbAssemblyMetadata.Database = @()
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -Be 0
        $splatDbAssemblyMetadata.Database = $null
        @(Get-DbaDbAssembly @splatDbAssemblyMetadata).Count | Should -Be 0
    }

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :21 documents wildcards for -Database; :104 filters with literal -in, so the
            # documented form never took effect (dead parameter form). -Name stays exact (help :25).
            $dbAssemblyWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $dbAssemblyWildcardNames = @(
                "${dbAssemblyWildcardPrefix}_a"
                "${dbAssemblyWildcardPrefix}_b"
                "${dbAssemblyWildcardPrefix}_[a]"
            )
            $dbAssemblyWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($dbAssemblyWildcardName in $dbAssemblyWildcardNames) {
                $dbAssemblyWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $dbAssemblyServer, $dbAssemblyWildcardName
                $dbAssemblyWildcardDatabase.Create()
                $dbAssemblyWildcardCreated.Add($dbAssemblyWildcardName)
                if ($null -eq $dbAssemblyWildcardDatabase.Assemblies["Microsoft.SqlServer.Types"]) {
                    throw "The wildcard fixture database lacks the system Microsoft.SqlServer.Types assembly"
                }
            }
        }

        AfterAll {
            $dbAssemblyServer.Databases.Refresh()
            foreach ($dbAssemblyWildcardName in $dbAssemblyWildcardCreated) {
                if ($dbAssemblyServer.Databases[$dbAssemblyWildcardName]) {
                    $dbAssemblyServer.KillDatabase($dbAssemblyWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatDbAssemblyWildcard = @{
                SqlInstance     = $dbAssemblyServer
                Database        = "${dbAssemblyWildcardPrefix}_*"
                Name            = "Microsoft.SqlServer.Types"
                EnableException = $true
            }
            $dbAssemblyWildcardRows = @(Get-DbaDbAssembly @splatDbAssemblyWildcard)
            (($dbAssemblyWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($dbAssemblyWildcardNames | Sort-Object) -join ",")
            $splatDbAssemblyWildcard.Database = "${dbAssemblyWildcardPrefix}_?"
            $dbAssemblyWildcardRows = @(Get-DbaDbAssembly @splatDbAssemblyWildcard)
            (($dbAssemblyWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($dbAssemblyWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "keeps bracket-only, invalid and SMO-object database values literal" {
            $splatDbAssemblyLiteral = @{
                SqlInstance     = $dbAssemblyServer
                Database        = $dbAssemblyWildcardNames[2]
                Name            = "Microsoft.SqlServer.Types"
                EnableException = $true
            }
            $dbAssemblyLiteralRows = @(Get-DbaDbAssembly @splatDbAssemblyLiteral)
            ($dbAssemblyLiteralRows.Database -join ",") | Should -BeExactly $dbAssemblyWildcardNames[2]
            $splatDbAssemblyLiteral.Database = "${dbAssemblyWildcardPrefix}_[*"
            @(Get-DbaDbAssembly @splatDbAssemblyLiteral).Count | Should -Be 0
            # Pinned public/New-DbaDbAsymmetricKey.ps1:181 binds an SMO database, which becomes "[name]".
            $dbAssemblyServer.Databases.Refresh()
            $splatDbAssemblyLiteral.Database = $dbAssemblyServer.Databases[$dbAssemblyWildcardNames[0]]
            @(Get-DbaDbAssembly @splatDbAssemblyLiteral).Count | Should -Be 0
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :21 documents -Database wildcards): a value equal to a real database name stays
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
            $dbAssemblyRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $dbAssemblyRealNameNames = @("${dbAssemblyRealNamePrefix}_*", "${dbAssemblyRealNamePrefix}_?", "${dbAssemblyRealNamePrefix}_x")
            $dbAssemblyRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($dbAssemblyRealNameIndex in 0, 1, 2) {
                $dbAssemblyRealNameName = $dbAssemblyRealNameNames[$dbAssemblyRealNameIndex]
                $dbAssemblyRealNameDatabase = New-NativeWildcardNameDatabase -Server $dbAssemblyServer -Name $dbAssemblyRealNameName -FileStem ("${dbAssemblyRealNamePrefix}_file" + $dbAssemblyRealNameIndex)
                $dbAssemblyRealNameCreated.Add($dbAssemblyRealNameName)
            }
        }

        AfterAll {
            $dbAssemblyServer.Databases.Refresh()
            foreach ($dbAssemblyRealNameName in $dbAssemblyRealNameCreated) {
                if ($dbAssemblyServer.Databases[$dbAssemblyRealNameName]) {
                    $dbAssemblyServer.KillDatabase($dbAssemblyRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatDbAssemblyRealNameExact = @{
                SqlInstance     = $dbAssemblyServer
                Database        = $dbAssemblyRealNameNames[0]
                Name            = "Microsoft.SqlServer.Types"
                EnableException = $true
            }
            $dbAssemblyRealNameRows = @(Get-DbaDbAssembly @splatDbAssemblyRealNameExact)
            (($dbAssemblyRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $dbAssemblyRealNameNames[0]
            $splatDbAssemblyRealNameExact.Database = $dbAssemblyRealNameNames[1].ToUpperInvariant()
            $dbAssemblyRealNameRows = @(Get-DbaDbAssembly @splatDbAssemblyRealNameExact)
            (($dbAssemblyRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $dbAssemblyRealNameNames[1]
            $splatDbAssemblyRealNameExact.Database = $dbAssemblyRealNameNames[0, 1]
            $dbAssemblyRealNameRows = @(Get-DbaDbAssembly @splatDbAssemblyRealNameExact)
            (($dbAssemblyRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($dbAssemblyRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatDbAssemblyRealNamePattern = @{
                SqlInstance     = $dbAssemblyServer
                Database        = "${dbAssemblyRealNamePrefix}*"
                Name            = "Microsoft.SqlServer.Types"
                EnableException = $true
            }
            $dbAssemblyRealNameRows = @(Get-DbaDbAssembly @splatDbAssemblyRealNamePattern)
            (($dbAssemblyRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($dbAssemblyRealNameNames | Sort-Object) -join ",")
        }
    }

    It "warns and continues distinct pipeline records around a failed connection" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $dbAssemblyWarnings = @()
        $dbAssemblyPreviousErrors = @($global:Error)
        $splatDbAssemblyPipeline = @{
            Database        = "master"
            Name            = "Microsoft.SqlServer.Types"
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "dbAssemblyWarnings"
        }
        $dbAssemblyPipelineRows = @(
            @($dbAssemblyServer, $dbAssemblyBadInstance, $dbAssemblySecondServer) |
                Get-DbaDbAssembly @splatDbAssemblyPipeline
        )
        $dbAssemblyPipelineRows.Count | Should -Be 2
        [object]::ReferenceEquals($dbAssemblyPipelineRows[0].Parent.Parent, $dbAssemblyServer) | Should -BeTrue
        [object]::ReferenceEquals($dbAssemblyPipelineRows[1].Parent.Parent, $dbAssemblySecondServer) | Should -BeTrue
        ($dbAssemblyWarnings -join " ") | Should -BeLike "*Failure*"
        $dbAssemblyConnectionError = $global:Error | Where-Object {
            $dbAssemblyPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbAssembly*"
        } | Select-Object -First 1
        $dbAssemblyConnectionError | Should -Not -BeNullOrEmpty
        $dbAssemblyConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "terminates at the failing pipeline connection under EnableException" -Tag "NativeChecklist:enable-exception" {
        $dbAssemblyObserved = New-Object System.Collections.ArrayList
        $dbAssemblyTerminatingError = $null
        $splatDbAssemblyException = @{
            Database        = "master"
            Name            = "Microsoft.SqlServer.Types"
            EnableException = $true
        }
        try {
            @($dbAssemblyServer, $dbAssemblyBadInstance, $dbAssemblySecondServer) |
                Get-DbaDbAssembly @splatDbAssemblyException |
                ForEach-Object { $null = $dbAssemblyObserved.Add($PSItem) }
        } catch {
            $dbAssemblyTerminatingError = $PSItem
        }
        $dbAssemblyTerminatingError | Should -Not -BeNullOrEmpty
        $dbAssemblyTerminatingError.CategoryInfo.Category | Should -Be "ConnectionError"
        $dbAssemblyTerminatingError.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbAssembly*"
        $dbAssemblyTerminatingError.Exception.Message | Should -Match "^The wait operation timed out\.?$"
        $dbAssemblyObserved.Count | Should -Be 1
        [object]::ReferenceEquals($dbAssemblyObserved[0].Parent.Parent, $dbAssemblyServer) | Should -BeTrue
    }
}

Describe "Native Get-DbaDbAssembly on Azure SQL Database" -Tag IntegrationTests {
    It "lists the assemblies of an Azure SQL Database as sys.assemblies does" -Tag "NativeChecklist:azure-sqldb" {
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
        # Read-only: nothing is created in the shared database. The connection's database is the Azure database.
        $azureExpected = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.assemblies;").Tables[0].Rows | ForEach-Object { [string]$PSItem.name } | Sort-Object)
        $splatAzureAssembly = @{
            SqlInstance     = $azureServer
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbAssembly @splatAzureAssembly)
        (($azureRows | ForEach-Object { $PSItem.Name } | Sort-Object) -join ",") | Should -BeExactly ($azureExpected -join ",")
        @($azureRows | Where-Object Database -cne $TestConfig.AzureSqlDbName).Count | Should -Be 0
        @($azureRows | Where-Object SqlInstance -cne $azureServer.DomainInstanceName).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbAssembly over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $splatLoginAssembly = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = "master"
                Name            = "Microsoft.SqlServer.Types"
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbAssembly @splatLoginAssembly)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Database | Should -BeExactly "master"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = "master"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbAssembly @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbAssembly -SqlInstance $loginInstance -Database "master" -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
