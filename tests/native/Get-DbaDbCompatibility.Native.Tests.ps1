#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbCompatibility",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters, despite stale help text mentioning them.
Describe "Native database compatibility behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeCompatibilityServer = $null
        $splatNativeCompatibilityConnect = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeCompatibilityServer = Connect-DbaInstance @splatNativeCompatibilityConnect
        $nativeCompatibilityMaster = $nativeCompatibilityServer.Databases["master"]
        $nativeCompatibilityTemp = $nativeCompatibilityServer.Databases["tempdb"]
    }

    AfterAll {
        if ($nativeCompatibilityServer) { $nativeCompatibilityServer.ConnectionContext.Disconnect() }
    }

    It "preserves enum values and reads a command-line SqlInstance once across pipeline databases" -Tag "NativeChecklist:pipeline-multiple" {
        # Pinned public/Get-DbaDbCompatibility.ps1:91-93 appends Get-DbaDatabase -SqlInstance to the
        # rebound InputObject on every piped record, duplicating the instance rows (wrong data).
        # The port reads a command-line SqlInstance once, after the first record of piped objects.
        $splatNativeCompatibilityMixed = @{
            SqlInstance     = $nativeCompatibilityServer
            Database        = "master"
            EnableException = $true
            Verbose         = $true
        }
        $nativeCompatibilityMessages = @(
            @($nativeCompatibilityMaster, $nativeCompatibilityTemp) |
                Get-DbaDbCompatibility @splatNativeCompatibilityMixed 4>&1
        )
        $nativeCompatibilityRows = @($nativeCompatibilityMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
        $nativeCompatibilityRows.Count | Should -Be 3
        ($nativeCompatibilityRows.Database -join ",") | Should -BeExactly "master,master,tempdb"
        foreach ($nativeCompatibilityRow in $nativeCompatibilityRows) {
            ($nativeCompatibilityRow.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,DatabaseId,Compatibility"
            $nativeCompatibilityRow.ComputerName | Should -BeExactly $nativeCompatibilityServer.ComputerName
            $nativeCompatibilityRow.InstanceName | Should -BeExactly $nativeCompatibilityServer.ServiceName
            $nativeCompatibilityRow.SqlInstance | Should -BeExactly $nativeCompatibilityServer.DomainInstanceName
            $nativeCompatibilityRow.DatabaseId | Should -Be $nativeCompatibilityServer.Databases[$nativeCompatibilityRow.Database].ID
            $nativeCompatibilityRow.Compatibility | Should -BeOfType Microsoft.SqlServer.Management.Smo.CompatibilityLevel
            $nativeCompatibilityRow.Compatibility | Should -Be $nativeCompatibilityServer.Databases[$nativeCompatibilityRow.Database].CompatibilityLevel
            $nativeCompatibilityRow.PSObject.Members["PSStandardMembers"] | Should -BeNullOrEmpty
        }
        $nativeCompatibilityVerbose = @($nativeCompatibilityMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*SQL Server is using Version:*" })
        $nativeCompatibilityVerbose.Count | Should -Be 3
        foreach ($nativeCompatibilityVersionMessage in $nativeCompatibilityVerbose) {
            $nativeCompatibilityVersionMessage.Message | Should -BeLike "*SQL Server is using Version: $($nativeCompatibilityServer.VersionMajor)*"
        }
    }

    It "uses literal case-insensitive database names and distinguishes bound empty input from absent input" {
        $splatNativeCompatibilityFilter = @{
            SqlInstance     = $nativeCompatibilityServer
            Database        = "MASTER"
            EnableException = $true
        }
        $nativeCompatibilityFiltered = @(Get-DbaDbCompatibility @splatNativeCompatibilityFilter)
        $nativeCompatibilityFiltered.Count | Should -Be 1
        $nativeCompatibilityFiltered[0].Database | Should -BeExactly "master"
        $nativeCompatibilityEmptyWarnings = @()
        $splatNativeCompatibilityEmpty = @{
            InputObject     = @()
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeCompatibilityEmptyWarnings"
        }
        @(Get-DbaDbCompatibility @splatNativeCompatibilityEmpty).Count | Should -Be 0
        $nativeCompatibilityEmptyWarnings | Should -BeNullOrEmpty
    }

    It "warns without input with either EnableException value" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        foreach ($nativeCompatibilityNoInputEnable in $false, $true) {
            $nativeCompatibilityNoInputWarnings = @()
            $splatNativeCompatibilityNoInput = @{
                EnableException = $nativeCompatibilityNoInputEnable
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeCompatibilityNoInputWarnings"
            }
            @(Get-DbaDbCompatibility @splatNativeCompatibilityNoInput).Count | Should -Be 0
            ($nativeCompatibilityNoInputWarnings -join " ") | Should -BeLike "*You must specify either a SQL instance or pipe a database collection*"
        }
    }

    It "continues discovery past a failed instance without forwarding EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeCompatibilitySavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeCompatibilityListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeCompatibilityListener.Start()
            $nativeCompatibilityBadInstance = "127.0.0.1," + $nativeCompatibilityListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            foreach ($nativeCompatibilityFailureEnable in $false, $true) {
                $nativeCompatibilityFailureWarnings = @()
                $nativeCompatibilityPriorErrors = @($global:Error)
                $splatNativeCompatibilityFailure = @{
                    SqlInstance     = @($nativeCompatibilityServer, $nativeCompatibilityBadInstance, $nativeCompatibilityServer)
                    Database        = "master"
                    EnableException = $nativeCompatibilityFailureEnable
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "nativeCompatibilityFailureWarnings"
                }
                $nativeCompatibilityContinued = @(Get-DbaDbCompatibility @splatNativeCompatibilityFailure)
                $nativeCompatibilityContinued.Count | Should -Be 2
                ($nativeCompatibilityContinued.Database -join ",") | Should -BeExactly "master,master"
                ($nativeCompatibilityFailureWarnings -join " ") | Should -BeLike "*Failure*"
                $nativeCompatibilityConnectionError = $global:Error | Where-Object {
                    $nativeCompatibilityPriorErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
                } | Select-Object -First 1
                $nativeCompatibilityConnectionError | Should -Not -BeNullOrEmpty
                $nativeCompatibilityConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
                # Stop-Function assigns the transformed target through the pipeline, leaving the instance name string.
                $nativeCompatibilityConnectionError.TargetObject.GetType().FullName | Should -BeExactly "System.String"
                $nativeCompatibilityConnectionError.TargetObject | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$nativeCompatibilityBadInstance).FullSmoName
            }
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeCompatibilitySavedTimeout
            $nativeCompatibilityListener.Stop()
        }
    }

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :20 documents wildcards for -Database; :92 delegates to the exact-match
            # Get-DbaDatabase, so the documented form never took effect (dead parameter form).
            $nativeCompatibilityWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeCompatibilityWildcardNames = @(
                "${nativeCompatibilityWildcardPrefix}_a"
                "${nativeCompatibilityWildcardPrefix}_b"
                "${nativeCompatibilityWildcardPrefix}_[a]"
            )
            $nativeCompatibilityWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeCompatibilityWildcardName in $nativeCompatibilityWildcardNames) {
                $nativeCompatibilityWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeCompatibilityServer, $nativeCompatibilityWildcardName
                $nativeCompatibilityWildcardDatabase.Create()
                $nativeCompatibilityWildcardCreated.Add($nativeCompatibilityWildcardName)
            }
        }

        AfterAll {
            $nativeCompatibilityServer.Databases.Refresh()
            foreach ($nativeCompatibilityWildcardName in $nativeCompatibilityWildcardCreated) {
                if ($nativeCompatibilityServer.Databases[$nativeCompatibilityWildcardName]) {
                    $nativeCompatibilityServer.KillDatabase($nativeCompatibilityWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatNativeCompatibilityWildcard = @{
                SqlInstance     = $nativeCompatibilityServer
                Database        = "${nativeCompatibilityWildcardPrefix}_*"
                EnableException = $true
            }
            $nativeCompatibilityWildcardRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityWildcard)
            (($nativeCompatibilityWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeCompatibilityWildcardNames | Sort-Object) -join ",")
            $splatNativeCompatibilityWildcard.Database = "${nativeCompatibilityWildcardPrefix}_?"
            $nativeCompatibilityWildcardRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityWildcard)
            (($nativeCompatibilityWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeCompatibilityWildcardNames[0, 1] | Sort-Object) -join ",")
            $splatNativeCompatibilityWildcard.Database = @("${nativeCompatibilityWildcardPrefix}_?", $nativeCompatibilityWildcardNames[2].ToUpperInvariant())
            $nativeCompatibilityWildcardRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityWildcard)
            (($nativeCompatibilityWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeCompatibilityWildcardNames | Sort-Object) -join ",")
        }

        It "keeps bracket-only and invalid wildcard values literal" {
            $splatNativeCompatibilityLiteral = @{
                SqlInstance     = $nativeCompatibilityServer
                Database        = $nativeCompatibilityWildcardNames[2]
                EnableException = $true
            }
            $nativeCompatibilityLiteralRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityLiteral)
            ($nativeCompatibilityLiteralRows.Database -join ",") | Should -BeExactly $nativeCompatibilityWildcardNames[2]
            $splatNativeCompatibilityLiteral.Database = "${nativeCompatibilityWildcardPrefix}_[*"
            @(Get-DbaDbCompatibility @splatNativeCompatibilityLiteral).Count | Should -Be 0
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
            $nativeCompatibilityRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeCompatibilityRealNameNames = @("${nativeCompatibilityRealNamePrefix}_*", "${nativeCompatibilityRealNamePrefix}_?", "${nativeCompatibilityRealNamePrefix}_x")
            $nativeCompatibilityRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeCompatibilityRealNameIndex in 0, 1, 2) {
                $nativeCompatibilityRealNameName = $nativeCompatibilityRealNameNames[$nativeCompatibilityRealNameIndex]
                $nativeCompatibilityRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeCompatibilityServer -Name $nativeCompatibilityRealNameName -FileStem ("${nativeCompatibilityRealNamePrefix}_file" + $nativeCompatibilityRealNameIndex)
                $nativeCompatibilityRealNameCreated.Add($nativeCompatibilityRealNameName)
            }
        }

        AfterAll {
            $nativeCompatibilityServer.Databases.Refresh()
            foreach ($nativeCompatibilityRealNameName in $nativeCompatibilityRealNameCreated) {
                if ($nativeCompatibilityServer.Databases[$nativeCompatibilityRealNameName]) {
                    $nativeCompatibilityServer.KillDatabase($nativeCompatibilityRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeCompatibilityRealNameExact = @{
                SqlInstance     = $nativeCompatibilityServer
                Database        = $nativeCompatibilityRealNameNames[0]
                EnableException = $true
            }
            $nativeCompatibilityRealNameRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityRealNameExact)
            (($nativeCompatibilityRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $nativeCompatibilityRealNameNames[0]
            $splatNativeCompatibilityRealNameExact.Database = $nativeCompatibilityRealNameNames[1].ToUpperInvariant()
            $nativeCompatibilityRealNameRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityRealNameExact)
            (($nativeCompatibilityRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $nativeCompatibilityRealNameNames[1]
            $splatNativeCompatibilityRealNameExact.Database = $nativeCompatibilityRealNameNames[0, 1]
            $nativeCompatibilityRealNameRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityRealNameExact)
            (($nativeCompatibilityRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeCompatibilityRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeCompatibilityRealNamePattern = @{
                SqlInstance     = $nativeCompatibilityServer
                Database        = "${nativeCompatibilityRealNamePrefix}*"
                EnableException = $true
            }
            $nativeCompatibilityRealNameRows = @(Get-DbaDbCompatibility @splatNativeCompatibilityRealNamePattern)
            (($nativeCompatibilityRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeCompatibilityRealNameNames | Sort-Object) -join ",")
        }
    }

    It "retains a null element in an explicit input array as a null-valued row" {
        $nativeCompatibilityNullableRows = @(Get-DbaDbCompatibility -InputObject @($null, $nativeCompatibilityMaster))
        $nativeCompatibilityNullableRows.Count | Should -Be 2
        foreach ($nativeCompatibilityNullProperty in $nativeCompatibilityNullableRows[0].PSObject.Properties) {
            $nativeCompatibilityNullProperty.Value | Should -BeNullOrEmpty
        }
        $nativeCompatibilityNullableRows[1].Database | Should -BeExactly "master"
    }
}

Describe "Native Get-DbaDbCompatibility on Azure SQL Database" -Tag IntegrationTests {
    It "reads the compatibility level of an Azure SQL Database by -SqlInstance and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
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
        $azureExpected = [int]$azureServer.ConnectionContext.ExecuteScalar("SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME();")
        $splatAzureCompatibility = @{
            SqlInstance     = $azureServer
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbCompatibility @splatAzureCompatibility)
        $azureRows.Count | Should -Be 1
        $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        [int]$azureRows[0].Compatibility | Should -Be $azureExpected
        $azurePipedRows = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbCompatibility -EnableException)
        $azurePipedRows.Count | Should -Be 1
        [int]$azurePipedRows[0].Compatibility | Should -Be $azureExpected
    }
}

Describe "Native Get-DbaDbCompatibility over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $splatLoginCompatibility = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = "master"
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbCompatibility @splatLoginCompatibility)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Database | Should -BeExactly "master"
            $loginRows[0].Compatibility | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested database gather, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = "master"
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbCompatibility @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
