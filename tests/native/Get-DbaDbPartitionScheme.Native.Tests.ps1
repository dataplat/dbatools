#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbPartitionScheme",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native partition scheme behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeSchemeCreated = $false
        $nativeSchemeEmptyCreated = $false
        $nativeSchemeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSchemeDatabaseName = "native_partition_scheme_" + [Guid]::NewGuid().ToString("N")
        $nativeSchemeDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSchemeServer, $nativeSchemeDatabaseName
        $nativeSchemeDatabase.Create()
        $nativeSchemeCreated = $true
        $nativeSchemeEmptyDatabaseName = "native_partition_scheme_empty_" + [Guid]::NewGuid().ToString("N")
        $nativeSchemeEmptyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSchemeServer, $nativeSchemeEmptyDatabaseName
        $nativeSchemeEmptyDatabase.Create()
        $nativeSchemeEmptyCreated = $true
        $nativeSchemeName = "native_scheme_a"
        $nativeSchemeOther = "native_scheme_b"
        $nativeSchemeFunction = "native_scheme_function"
        $nativeSchemeDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [$nativeSchemeFunction] (int) AS RANGE LEFT FOR VALUES (10, 20); CREATE PARTITION SCHEME [$nativeSchemeName] AS PARTITION [$nativeSchemeFunction] ALL TO ([PRIMARY]); CREATE PARTITION SCHEME [$nativeSchemeOther] AS PARTITION [$nativeSchemeFunction] ALL TO ([PRIMARY]);")
        $nativeSchemeDisplay = "ComputerName,InstanceName,SqlInstance,Database,Name,PartitionFunction"
    }

    AfterAll {
        if ($nativeSchemeEmptyCreated) {
            $splatRemoveNativeSchemeEmptyDatabase = @{
                SqlInstance     = $nativeSchemeServer
                Database        = $nativeSchemeEmptyDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeSchemeEmptyDatabase
        }
        if ($nativeSchemeCreated) {
            $splatRemoveNativeSchemeDatabase = @{
                SqlInstance     = $nativeSchemeServer
                Database        = $nativeSchemeDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeSchemeDatabase
        }
    }

    It "preserves typed schemes, Name alias filtering and instance/display metadata on repeated reads" {
        $splatNativeSchemeRead = @{
            SqlInstance     = $nativeSchemeServer
            Database        = $nativeSchemeDatabaseName.ToUpperInvariant()
            Name            = $nativeSchemeName.ToUpperInvariant()
            EnableException = $true
        }
        foreach ($nativeSchemeIteration in 1, 2) {
            $nativeSchemeRows = @(Get-DbaDbPartitionScheme @splatNativeSchemeRead)
            $nativeSchemeRows.Count | Should -Be 1
            $nativeSchemeRow = $nativeSchemeRows[0]
            $nativeSchemeRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.PartitionScheme
            $nativeSchemeRow.Name | Should -BeExactly $nativeSchemeName
            $nativeSchemeRow.Database | Should -BeExactly $nativeSchemeDatabaseName
            $nativeSchemeRow.ComputerName | Should -BeExactly $nativeSchemeServer.ComputerName
            $nativeSchemeRow.InstanceName | Should -BeExactly $nativeSchemeServer.ServiceName
            $nativeSchemeRow.SqlInstance | Should -BeExactly $nativeSchemeServer.DomainInstanceName
            $nativeSchemeRow.PartitionFunction | Should -BeExactly $nativeSchemeFunction
            ($nativeSchemeRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeSchemeDisplay
            @($nativeSchemeRow.PSObject.Properties | Where-Object Name -eq "Database").Count | Should -Be 1
        }
    }

    It "preserves literal database membership and exclusion precedence" {
        $splatNativeSchemeFilter = @{
            SqlInstance     = $nativeSchemeServer
            Database        = $nativeSchemeDatabaseName
            PartitionScheme = @($nativeSchemeName, $nativeSchemeOther)
            EnableException = $true
        }
        @(Get-DbaDbPartitionScheme @splatNativeSchemeFilter).Count | Should -Be 2
        $splatNativeSchemeFilter.ExcludeDatabase = $nativeSchemeDatabaseName.ToUpperInvariant()
        @(Get-DbaDbPartitionScheme @splatNativeSchemeFilter).Count | Should -Be 0
        $splatNativeSchemeFilter.Remove("ExcludeDatabase")
        $splatNativeSchemeFilter.Database = "native_partition_scheme_*"
        @(Get-DbaDbPartitionScheme @splatNativeSchemeFilter).Count | Should -Be 0
    }

    It "treats scheme wildcards literally and emits the empty-match verbose message" {
        $splatNativeSchemeMissing = @{
            SqlInstance     = $nativeSchemeServer
            Database        = $nativeSchemeDatabaseName
            PartitionScheme = "native_scheme_*"
            EnableException = $true
            Verbose         = $true
        }
        $nativeSchemeMessages = @(Get-DbaDbPartitionScheme @splatNativeSchemeMissing 4>&1)
        @($nativeSchemeMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        $nativeSchemeVerbose = @($nativeSchemeMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] })
        ($nativeSchemeVerbose.Message -join " ") | Should -BeLike "*No Partition Schemes exist in the *$nativeSchemeDatabaseName* database on *"
    }

    It "keeps an unfiltered empty collection silent but reports a filtered empty match" {
        $splatNativeSchemeEmpty = @{
            SqlInstance     = $nativeSchemeServer
            Database        = $nativeSchemeEmptyDatabaseName
            EnableException = $true
            Verbose         = $true
        }
        $nativeSchemeEmptyMessages = @(Get-DbaDbPartitionScheme @splatNativeSchemeEmpty 4>&1)
        @($nativeSchemeEmptyMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        @($nativeSchemeEmptyMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Partition Schemes exist*" }).Count | Should -Be 0

        $splatNativeSchemeEmpty.PartitionScheme = "missing_scheme"
        $nativeSchemeEmptyFilteredMessages = @(Get-DbaDbPartitionScheme @splatNativeSchemeEmpty 4>&1)
        @($nativeSchemeEmptyFilteredMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        @($nativeSchemeEmptyFilteredMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Partition Schemes exist*" }).Count | Should -Be 1
    }

    It "continues after connection failure or terminates with earlier output when EnableException is enabled" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeSchemeTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeSchemeListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeSchemeListener.Start()
            $nativeSchemeBadInstance = "127.0.0.1," + $nativeSchemeListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeSchemeWarnings = @()
            $splatNativeSchemeFailure = @{
                Database        = $nativeSchemeDatabaseName
                PartitionScheme = $nativeSchemeName
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeSchemeWarnings"
            }
            $nativeSchemeContinued = @(
                @($nativeSchemeServer, $nativeSchemeBadInstance, $nativeSchemeServer) |
                    Get-DbaDbPartitionScheme @splatNativeSchemeFailure
            )
            $nativeSchemeContinued.Count | Should -Be 2
            @($nativeSchemeContinued | Where-Object Name -ne $nativeSchemeName).Count | Should -Be 0
            ($nativeSchemeWarnings -join " ") | Should -BeLike "*Failure*"

            $splatNativeSchemeFailure.EnableException = $true
            $nativeSchemeEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeSchemeCaught = $null
            try {
                @($nativeSchemeServer, $nativeSchemeBadInstance, $nativeSchemeServer) |
                    Get-DbaDbPartitionScheme @splatNativeSchemeFailure |
                    ForEach-Object { $nativeSchemeEarlier.Add($PSItem) }
            } catch {
                $nativeSchemeCaught = $PSItem
            }
            $nativeSchemeEarlier.Count | Should -Be 1
            $nativeSchemeEarlier[0].Name | Should -BeExactly $nativeSchemeName
            $nativeSchemeCaught | Should -Not -BeNullOrEmpty
            $nativeSchemeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $nativeSchemeCaught.TargetObject | Should -BeExactly $nativeSchemeBadInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeSchemeTimeout
            $nativeSchemeListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbPartitionScheme numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeSchemeNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeSchemeNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeSchemeNumberNames = @("0$nativeSchemeNumber", "$nativeSchemeNumber")
        $nativeSchemeNumberCreated = @()
        foreach ($nativeSchemeNumberName in $nativeSchemeNumberNames) {
            $nativeSchemeNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeSchemeNumberServer, $nativeSchemeNumberName
            $nativeSchemeNumberDatabase.Create()
            $nativeSchemeNumberCreated += $nativeSchemeNumberName
            $nativeSchemeNumberDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_number_pf] (int) AS RANGE LEFT FOR VALUES (1); CREATE PARTITION SCHEME [native_number_ps] AS PARTITION [native_number_pf] ALL TO ([PRIMARY]);")
        }
    }

    AfterAll {
        if ($nativeSchemeNumberCreated.Count -gt 0) {
            $splatRemoveNativeSchemeNumberDatabase = @{
                SqlInstance     = $nativeSchemeNumberServer
                Database        = $nativeSchemeNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeSchemeNumberDatabase
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeSchemeNumberInclude = @{
            SqlInstance     = $nativeSchemeNumberServer
            Database        = [int]$nativeSchemeNumber
            EnableException = $true
        }
        $nativeSchemeNumberIncluded = @(Get-DbaDbPartitionScheme @splatNativeSchemeNumberInclude)
        (($nativeSchemeNumberIncluded.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeSchemeNumberNames | Sort-Object) -join ",")

        $splatNativeSchemeNumberExclude = @{
            SqlInstance     = $nativeSchemeNumberServer
            Database        = $nativeSchemeNumberNames
            ExcludeDatabase = [int]$nativeSchemeNumber
            EnableException = $true
        }
        @(Get-DbaDbPartitionScheme @splatNativeSchemeNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbPartitionScheme on Azure SQL Database" -Tag IntegrationTests {
    It "reads a partition scheme in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
        # Six legs share the database: unique names and cleanup. Azure SQL Database has only the PRIMARY filegroup.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azureFunctionName = "native_pf_azure_$azureSuffix"
        $azureSchemeName = "native_ps_azure_$azureSuffix"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE PARTITION FUNCTION [$azureFunctionName] (int) AS RANGE LEFT FOR VALUES (10, 20);")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE PARTITION SCHEME [$azureSchemeName] AS PARTITION [$azureFunctionName] ALL TO ([PRIMARY]);")
            $splatAzurePartition = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                PartitionScheme = $azureSchemeName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbPartitionScheme @splatAzurePartition)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.PartitionScheme
            $azureRows[0].Name | Should -BeExactly $azureSchemeName
            $azureRows[0].PartitionFunction | Should -BeExactly $azureFunctionName
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'$azureSchemeName') DROP PARTITION SCHEME [$azureSchemeName]; IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'$azureFunctionName') DROP PARTITION FUNCTION [$azureFunctionName];")
        }
    }
}

Describe "Native Get-DbaDbPartitionScheme over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_ps_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION [native_login_pf] (int) AS RANGE LEFT FOR VALUES (10, 20); CREATE PARTITION SCHEME [native_login_ps] AS PARTITION [native_login_pf] ALL TO ([PRIMARY]);")
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
            $loginRows = @(Get-DbaDbPartitionScheme @splatLoginPartition)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_ps"
            $loginRows[0].PartitionFunction | Should -BeExactly "native_login_pf"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbPartitionScheme @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbPartitionScheme -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
