#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbPartitionFunction",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native partition function behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativePartitionCreated = $false
        $nativePartitionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePartitionDatabaseName = "native_partition_" + [Guid]::NewGuid().ToString("N")
        $nativePartitionDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePartitionServer, $nativePartitionDatabaseName
        $nativePartitionDatabase.Create()
        $nativePartitionCreated = $true
        $nativePartitionName = "native_partition_a"
        $nativePartitionOtherName = "native_partition_b"
        $splatCreatePartition = @{
            SqlInstance = $nativePartitionServer
            Database = $nativePartitionDatabaseName
            Query = "CREATE PARTITION FUNCTION [$nativePartitionName] (int) AS RANGE LEFT FOR VALUES (10, 20); CREATE PARTITION FUNCTION [$nativePartitionOtherName] (int) AS RANGE RIGHT FOR VALUES (30, 40);"
            EnableException = $true
        }
        $null = Invoke-DbaQuery @splatCreatePartition
        $nativePartitionBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativePartitionDisplay = "ComputerName,InstanceName,SqlInstance,Database,CreateDate,Name,NumberOfPartitions"
    }

    AfterAll {
        if ($nativePartitionCreated) {
            $splatRemovePartitionDatabase = @{
                SqlInstance = $nativePartitionServer
                Database = $nativePartitionDatabaseName
                Confirm = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemovePartitionDatabase
        }
    }

    It "preserves named filtering, SMO objects and display metadata on repeated reads" {
        $splatPartitionFilter = @{
            SqlInstance = $nativePartitionServer
            Database = $nativePartitionDatabaseName.ToUpperInvariant()
            Name = $nativePartitionName.ToUpperInvariant()
            EnableException = $true
        }
        foreach ($nativePartitionIteration in 1, 2) {
            $nativePartitionRows = @(Get-DbaDbPartitionFunction @splatPartitionFilter)
            $nativePartitionRows.Count | Should -Be 1
            $nativePartitionRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.PartitionFunction
            $nativePartitionRows[0].Name | Should -BeExactly $nativePartitionName
            $nativePartitionRows[0].Database | Should -BeExactly $nativePartitionDatabaseName
            $nativePartitionRows[0].InstanceName | Should -BeExactly $nativePartitionServer.ServiceName
            ($nativePartitionRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativePartitionDisplay
            @($nativePartitionRows[0].PSObject.Properties | Where-Object Name -eq "Database").Count | Should -Be 1
        }
    }

    It "lets database exclusion remove an explicitly included database" {
        $splatPartitionExclusion = @{
            SqlInstance = $nativePartitionServer
            Database = $nativePartitionDatabaseName
            ExcludeDatabase = $nativePartitionDatabaseName.ToUpperInvariant()
            EnableException = $true
        }
        @(Get-DbaDbPartitionFunction @splatPartitionExclusion).Count | Should -Be 0
    }

    It "warns for a failed middle pipeline instance and emits later results" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativePartitionWarnings = @()
        $splatPartitionPipeline = @{
            Database = $nativePartitionDatabaseName
            PartitionFunction = $nativePartitionName
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "nativePartitionWarnings"
        }
        $nativePartitionRows = @(
            @($nativePartitionServer, $nativePartitionBadInstance, $nativePartitionServer) |
                Get-DbaDbPartitionFunction @splatPartitionPipeline
        )
        $nativePartitionRows.Count | Should -Be 2
        $nativePartitionRows[0].Name | Should -BeExactly $nativePartitionName
        $nativePartitionRows[1].Name | Should -BeExactly $nativePartitionName
        ($nativePartitionWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "retains earlier output when EnableException terminates a failed pipeline" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $nativePartitionEarlierRows = New-Object "System.Collections.Generic.List[object]"
        $nativePartitionCaught = $null
        $splatPartitionTerminating = @{
            Database = $nativePartitionDatabaseName
            PartitionFunction = $nativePartitionName
            EnableException = $true
        }
        try {
            @($nativePartitionServer, $nativePartitionBadInstance, $nativePartitionServer) |
                Get-DbaDbPartitionFunction @splatPartitionTerminating |
                ForEach-Object { $nativePartitionEarlierRows.Add($PSItem) }
        } catch {
            $nativePartitionCaught = $PSItem
        }
        $nativePartitionEarlierRows.Count | Should -Be 1
        $nativePartitionEarlierRows[0].Name | Should -BeExactly $nativePartitionName
        $nativePartitionCaught | Should -Not -BeNullOrEmpty
        $nativePartitionCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativePartitionCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }

    # NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess or WhatIf/Confirm parameters.

    Context "Documented wildcard partition function selection" {
        BeforeAll {
            # Pinned help :28 documents wildcards for -PartitionFunction; :132 filters with literal -in,
            # so the documented form never took effect. Help :19-25 documents no database wildcards.
            $nativePartitionBracketName = "native_partition_[a]"
            $nativePartitionDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_partition_[a]]] (int) AS RANGE LEFT FOR VALUES (50);")
            $nativePartitionDatabase.PartitionFunctions.Refresh()
            if ($null -eq $nativePartitionDatabase.PartitionFunctions[$nativePartitionBracketName]) {
                throw "The bracket-named partition function fixture is absent"
            }
        }

        AfterAll {
            $nativePartitionDatabase.PartitionFunctions.Refresh()
            $nativePartitionBracketCleanup = $nativePartitionDatabase.PartitionFunctions[$nativePartitionBracketName]
            if ($null -ne $nativePartitionBracketCleanup) { $nativePartitionBracketCleanup.Drop() }
        }

        It "selects partition functions by a documented wildcard pattern" {
            $splatPartitionWildcard = @{
                SqlInstance       = $nativePartitionServer
                Database          = $nativePartitionDatabaseName
                PartitionFunction = "NATIVE_PARTITION_?"
                EnableException   = $true
            }
            $nativePartitionWildcardRows = @(Get-DbaDbPartitionFunction @splatPartitionWildcard)
            (($nativePartitionWildcardRows.Name | Sort-Object) -join ",") | Should -BeExactly "$nativePartitionName,$nativePartitionOtherName"
            $splatPartitionWildcard.PartitionFunction = "native_partition_*"
            $nativePartitionWildcardRows = @(Get-DbaDbPartitionFunction @splatPartitionWildcard)
            (($nativePartitionWildcardRows.Name | Sort-Object) -join ",") | Should -BeExactly ((@($nativePartitionName, $nativePartitionOtherName, $nativePartitionBracketName) | Sort-Object) -join ",")
        }

        It "keeps bracket-only, invalid and database wildcard values literal" {
            $splatPartitionLiteral = @{
                SqlInstance       = $nativePartitionServer
                Database          = $nativePartitionDatabaseName
                PartitionFunction = $nativePartitionBracketName
                EnableException   = $true
            }
            $nativePartitionLiteralRows = @(Get-DbaDbPartitionFunction @splatPartitionLiteral)
            ($nativePartitionLiteralRows.Name -join ",") | Should -BeExactly $nativePartitionBracketName
            $splatPartitionLiteral.PartitionFunction = "native_partition_[*"
            @(Get-DbaDbPartitionFunction @splatPartitionLiteral).Count | Should -Be 0
            $splatPartitionLiteral.Remove("PartitionFunction")
            $splatPartitionLiteral.Database = "native_partition_*"
            @(Get-DbaDbPartitionFunction @splatPartitionLiteral).Count | Should -Be 0
        }
    }

    Context "Real partition function names containing wildcard characters" {
        BeforeAll {
            # Rule E+: pinned help :28 documents -PartitionFunction wildcards, but a value equal to a
            # real partition function name of the database stays literal.
            $nativePartitionRealNames = @("native_wcpf_*", "native_wcpf_?", "native_wcpf_x")
            $nativePartitionDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_wcpf_*] (int) AS RANGE LEFT FOR VALUES (1); CREATE PARTITION FUNCTION [native_wcpf_?] (int) AS RANGE LEFT FOR VALUES (2); CREATE PARTITION FUNCTION [native_wcpf_x] (int) AS RANGE LEFT FOR VALUES (3);")
            $nativePartitionDatabase.PartitionFunctions.Refresh()
        }

        AfterAll {
            $nativePartitionDatabase.PartitionFunctions.Refresh()
            foreach ($nativePartitionRealName in $nativePartitionRealNames) {
                $nativePartitionRealCleanup = $nativePartitionDatabase.PartitionFunctions[$nativePartitionRealName]
                if ($null -ne $nativePartitionRealCleanup) { $nativePartitionRealCleanup.Drop() }
            }
        }

        It "selects a real partition function whose name contains * or ? alone by its exact name" {
            $splatPartitionRealExact = @{
                SqlInstance       = $nativePartitionServer
                Database          = $nativePartitionDatabaseName
                PartitionFunction = $nativePartitionRealNames[0]
                EnableException   = $true
            }
            (@(Get-DbaDbPartitionFunction @splatPartitionRealExact).Name -join ",") | Should -BeExactly $nativePartitionRealNames[0]
            $splatPartitionRealExact.PartitionFunction = $nativePartitionRealNames[1].ToUpperInvariant()
            (@(Get-DbaDbPartitionFunction @splatPartitionRealExact).Name -join ",") | Should -BeExactly $nativePartitionRealNames[1]
            $splatPartitionRealExact.PartitionFunction = $nativePartitionRealNames[0, 1]
            ((@(Get-DbaDbPartitionFunction @splatPartitionRealExact).Name | Sort-Object) -join ",") | Should -BeExactly (($nativePartitionRealNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside partition functions whose names contain * or ?" {
            $splatPartitionRealPattern = @{
                SqlInstance       = $nativePartitionServer
                Database          = $nativePartitionDatabaseName
                PartitionFunction = "native_wcpf*"
                EnableException   = $true
            }
            ((@(Get-DbaDbPartitionFunction @splatPartitionRealPattern).Name | Sort-Object) -join ",") | Should -BeExactly (($nativePartitionRealNames | Sort-Object) -join ",")
        }
    }

    Context "Empty partition function results" {
        BeforeAll {
            $nativePartitionEmptyCreated = $false
            $nativePartitionEmptyName = "native_partition_empty_" + [Guid]::NewGuid().ToString("N")
            $nativePartitionEmptyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePartitionServer, $nativePartitionEmptyName
            $nativePartitionEmptyDatabase.Create()
            $nativePartitionEmptyCreated = $true
        }

        AfterAll {
            if ($nativePartitionEmptyCreated) {
                $splatRemovePartitionEmpty = @{
                    SqlInstance     = $nativePartitionServer
                    Database        = $nativePartitionEmptyName
                    Confirm         = $false
                    EnableException = $true
                }
                Remove-DbaDatabase @splatRemovePartitionEmpty
            }
        }

        It "stays silent for an unfiltered database without partition functions" {
            # Pinned public/Get-DbaDbPartitionFunction.ps1:129-135 tests an unfiltered SMO collection,
            # which PowerShell treats as true even when empty because it is not an IList.
            $splatPartitionEmpty = @{
                SqlInstance     = $nativePartitionServer
                Database        = $nativePartitionEmptyName
                EnableException = $true
                Verbose         = $true
            }
            $nativePartitionEmptyRecords = @(Get-DbaDbPartitionFunction @splatPartitionEmpty 4>&1)
            @($nativePartitionEmptyRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            @($nativePartitionEmptyRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Partition Functions exist*" }).Count | Should -Be 0
        }

        It "writes the verbose message when a name filter matches nothing" {
            $splatPartitionNoMatch = @{
                SqlInstance       = $nativePartitionServer
                Database          = @($nativePartitionDatabaseName, $nativePartitionEmptyName)
                PartitionFunction = "native_partition_none"
                EnableException   = $true
                Verbose           = $true
            }
            $nativePartitionNoMatchRecords = @(Get-DbaDbPartitionFunction @splatPartitionNoMatch 4>&1)
            @($nativePartitionNoMatchRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            $nativePartitionNoMatchVerbose = @($nativePartitionNoMatchRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Partition Functions exist*" })
            $nativePartitionNoMatchVerbose.Count | Should -Be 2
            ($nativePartitionNoMatchVerbose.Message -join " ") | Should -BeLike "*No Partition Functions exist in the ``[$nativePartitionDatabaseName``] database on *"
            ($nativePartitionNoMatchVerbose.Message -join " ") | Should -BeLike "*No Partition Functions exist in the ``[$nativePartitionEmptyName``] database on *"
        }
    }
}

Describe "Native Get-DbaDbPartitionFunction numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativePartitionNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePartitionNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativePartitionNumberNames = @("0$nativePartitionNumber", "$nativePartitionNumber")
        $nativePartitionNumberCreated = @()
        foreach ($nativePartitionNumberName in $nativePartitionNumberNames) {
            $nativePartitionNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePartitionNumberServer, $nativePartitionNumberName
            $nativePartitionNumberDatabase.Create()
            $nativePartitionNumberCreated += $nativePartitionNumberName
            $nativePartitionNumberDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_number_pf] (int) AS RANGE LEFT FOR VALUES (1);")
        }
    }

    AfterAll {
        if ($nativePartitionNumberCreated.Count -gt 0) {
            $splatRemoveNativePartitionNumberDatabase = @{
                SqlInstance     = $nativePartitionNumberServer
                Database        = $nativePartitionNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativePartitionNumberDatabase
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativePartitionNumberInclude = @{
            SqlInstance     = $nativePartitionNumberServer
            Database        = [int]$nativePartitionNumber
            EnableException = $true
        }
        $nativePartitionNumberIncluded = @(Get-DbaDbPartitionFunction @splatNativePartitionNumberInclude)
        (($nativePartitionNumberIncluded.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativePartitionNumberNames | Sort-Object) -join ",")

        $splatNativePartitionNumberExclude = @{
            SqlInstance     = $nativePartitionNumberServer
            Database        = $nativePartitionNumberNames
            ExcludeDatabase = [int]$nativePartitionNumber
            EnableException = $true
        }
        @(Get-DbaDbPartitionFunction @splatNativePartitionNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbPartitionFunction on Azure SQL Database" -Tag IntegrationTests {
    It "reads a partition function in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        # Six legs share the database: a unique function and cleanup.
        $azureFunctionName = "native_pf_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE PARTITION FUNCTION [$azureFunctionName] (int) AS RANGE LEFT FOR VALUES (10, 20);")
            $splatAzurePartition = @{
                SqlInstance       = $azureServer
                Database          = $TestConfig.AzureSqlDbName
                PartitionFunction = $azureFunctionName
                EnableException   = $true
            }
            $azureRows = @(Get-DbaDbPartitionFunction @splatAzurePartition)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.PartitionFunction
            $azureRows[0].Name | Should -BeExactly $azureFunctionName
            $azureRows[0].NumberOfPartitions | Should -Be 3
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'$azureFunctionName') DROP PARTITION FUNCTION [$azureFunctionName];")
        }
    }
}

Describe "Native Get-DbaDbPartitionFunction over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_pf_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_login_pf] (int) AS RANGE LEFT FOR VALUES (10, 20);")
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
            $splatLoginPartition = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbPartitionFunction @splatLoginPartition)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_pf"
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
            $loginResult = @(Get-DbaDbPartitionFunction @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbPartitionFunction -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
