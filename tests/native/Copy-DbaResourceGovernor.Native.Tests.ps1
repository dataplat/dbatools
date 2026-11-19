#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaResourceGovernor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter takes pipeline input; several destinations are covered by the multi-instance tests.
# NativeChecklist: azure-sqldb N/A -- Resource Governor exists only in SQL Server and Azure SQL Managed Instance (ALTER RESOURCE GOVERNOR: https://learn.microsoft.com/sql/t-sql/statements/alter-resource-governor-transact-sql); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

BeforeAll {
    # The pinned file runs first in this process. Its AfterAll ends the dbatools sessions, but its next cleanup
    # connection opens while its classifier still routes new sessions to dbatoolsci_goffhoursprocessing, so its
    # DROP WORKLOAD GROUP ...; ALTER RESOURCE GOVERNOR RECONFIGURE fails and the drop stays pending while that pooled
    # session lives. Clear this process's pools and end only this process's sessions still in a dbatoolsci workload
    # group (the runtime DMV still lists a group whose drop is pending), so the first RECONFIGURE below completes.
    [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
    $rgOrphanQuery = "DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CONVERT(nvarchar(10), s.session_id) + N'; ' FROM sys.dm_exec_sessions AS s INNER JOIN sys.dm_resource_governor_workload_groups AS g ON g.group_id = s.group_id WHERE s.host_process_id = $PID AND s.session_id <> @@SPID AND g.name LIKE N'dbatoolsci[_]%'; EXEC (@kill);"
    foreach ($rgOrphanInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
        $rgOrphanServer = Connect-DbaInstance -SqlInstance $rgOrphanInstance -NonPooledConnection -EnableException
        try {
            $null = $rgOrphanServer.ConnectionContext.ExecuteNonQuery($rgOrphanQuery)
        } finally {
            $rgOrphanServer.ConnectionContext.Disconnect()
        }
    }
    [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()

    # The governor state of both copy instances, put back after each Describe: RECONFIGURE enables the governor.
    $rgStateQuery = "SELECT is_enabled FROM sys.resource_governor_configuration"
    function Get-NativeRgEnabled {
        param($Instance)
        [bool](Invoke-DbaQuery -SqlInstance $Instance -Database master -Query $rgStateQuery -EnableException).is_enabled
    }
    function Restore-NativeRgEnabled {
        param($Instance, $Enabled)
        if ($Enabled) {
            Invoke-DbaQuery -SqlInstance $Instance -Database master -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -EnableException
        } else {
            Invoke-DbaQuery -SqlInstance $Instance -Database master -Query "ALTER RESOURCE GOVERNOR RECONFIGURE; ALTER RESOURCE GOVERNOR DISABLE" -EnableException
        }
    }
    function Remove-NativeRgPool {
        param($Instance, $Pool, $Group)
        $splatDrop = @{
            SqlInstance     = $Instance
            Database        = "master"
            EnableException = $true
        }
        Invoke-DbaQuery @splatDrop -Query "IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'$Group') DROP WORKLOAD GROUP [$Group]"
        Invoke-DbaQuery @splatDrop -Query "IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'$Pool') DROP RESOURCE POOL [$Pool]"
    }
}

Describe "Native Copy-DbaResourceGovernor pools" -Tag IntegrationTests {
    BeforeAll {
        $nativeBadInstance = "TCP:127.0.0.1,1"
        $nativeSuffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
        # SMO lists pools by name, so pool a comes before pool b.
        $poolA = "native_rg_a_$nativeSuffix"
        $groupA = "native_rg_ga_$nativeSuffix"
        $poolB = "native_rg_b_$nativeSuffix"
        $groupB = "native_rg_gb_$nativeSuffix"
        $poolC = "native_rg_c_$nativeSuffix"
        $groupC = "native_rg_gc_$nativeSuffix"
        # A pool whose name -in converts to a number: "0123456789" -in @(123456789) is true.
        $numericValue = Get-Random -Minimum 100000000 -Maximum 999999999
        $poolNumeric = "0$numericValue"
        $groupNumeric = "native_rg_gn_$nativeSuffix"
        $sourceEnabled = Get-NativeRgEnabled -Instance $TestConfig.InstanceCopy1
        $destEnabled = Get-NativeRgEnabled -Instance $TestConfig.InstanceCopy2
        $splatSource = @{
            SqlInstance     = $TestConfig.InstanceCopy1
            Database        = "master"
            EnableException = $true
        }
        foreach ($pair in @(@($poolA, $groupA), @($poolB, $groupB), @($poolC, $groupC), @($poolNumeric, $groupNumeric))) {
            Invoke-DbaQuery @splatSource -Query "CREATE RESOURCE POOL [$($pair[0])] WITH (MAX_CPU_PERCENT = 40)"
            Invoke-DbaQuery @splatSource -Query "CREATE WORKLOAD GROUP [$($pair[1])] WITH (IMPORTANCE = LOW) USING [$($pair[0])]"
        }
        Invoke-DbaQuery @splatSource -Query "ALTER RESOURCE GOVERNOR RECONFIGURE"
        $nativeDest = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException

        function Get-NativeDestPool {
            param($Name)
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query "SELECT p.name AS pool, g.name AS grp FROM sys.resource_governor_resource_pools p LEFT JOIN sys.resource_governor_workload_groups g ON g.pool_id = p.pool_id WHERE p.name = N'$Name'" -EnableException
        }
    }

    AfterAll {
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($pair in @(@($poolA, $groupA), @($poolB, $groupB), @($poolC, $groupC), @($poolNumeric, $groupNumeric))) {
                Remove-NativeRgPool -Instance $instance -Pool $pair[0] -Group $pair[1]
            }
        }
        Restore-NativeRgEnabled -Instance $TestConfig.InstanceCopy1 -Enabled $sourceEnabled
        Restore-NativeRgEnabled -Instance $TestConfig.InstanceCopy2 -Enabled $destEnabled
    }

    It "copies a named pool with its workload group as MigrationObject rows" {
        $splatCopy = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = $poolB.ToUpperInvariant()
        }
        $result = @(Copy-DbaResourceGovernor @splatCopy)
        $poolRows = @($result | Where-Object Type -eq "Resource Governor Pool")
        $poolRows.Count | Should -Be 1
        $poolRows[0].Name | Should -BeExactly $poolB
        $poolRows[0].Status | Should -BeExactly "Successful"
        $poolRows[0].DestinationServer | Should -Be $nativeDest.Name
        $poolRows[0].PSObject.TypeNames[0] | Should -BeExactly "dbatools.MigrationObject"
        $groupRows = @($result | Where-Object Type -eq "Resource Governor Pool Workgroup")
        $groupRows.Name | Should -BeExactly $groupB
        $groupRows.Status | Should -BeExactly "Successful"
        ($result | Where-Object Type -eq "Reconfigure Resource Governor").Status | Should -BeExactly "Successful"
        $copied = @(Get-NativeDestPool -Name $poolB)
        $copied.grp | Should -Be $groupB
    }

    It "reports an existing pool as skipped without -Force and repeats no other pool's workload group" -Tag "NativeChecklist:switch-false" {
        $splatExisting = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = $poolA, $poolB
            Force        = $false
        }
        $result = @(Copy-DbaResourceGovernor @splatExisting)
        ($result | Where-Object Name -eq $poolA).Status | Should -BeExactly "Successful"
        $skipped = @($result | Where-Object Name -eq $poolB)
        $skipped.Count | Should -Be 1
        $skipped[0].Status | Should -BeExactly "Skipped"
        $skipped[0].Notes | Should -BeExactly "Already exists on destination"
        $groupRows = @($result | Where-Object Type -eq "Resource Governor Pool Workgroup")
        $groupRows.Count | Should -Be 1
        $groupRows[0].Name | Should -BeExactly $groupA
        $groupRows[0].Status | Should -BeExactly "Successful"
        @($result | Where-Object Status -eq "Failed").Count | Should -Be 0
    }

    It "leaves the system pools out of -ResourcePool, as its help says" {
        $splatSystem = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = "default", "internal", $poolA
        }
        $result = @(Copy-DbaResourceGovernor @splatSystem)
        @($result | Where-Object Type -eq "Resource Governor Pool").Name | Should -BeExactly @($poolA)
        @($result | Where-Object Name -in "default", "internal").Count | Should -Be 0
    }

    It "drops and recreates an existing pool and its workload group with -Force" {
        $splatForce = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = $poolA
            Force        = $true
        }
        $result = @(Copy-DbaResourceGovernor @splatForce)
        ($result | Where-Object Name -eq $poolA).Status | Should -BeExactly "Successful"
        ($result | Where-Object Name -eq $groupA).Status | Should -BeExactly "Successful"
        @(Get-NativeDestPool -Name $poolA).grp | Should -Be $groupA
    }

    It "changes nothing and returns nothing under -WhatIf, and copies with -Confirm:`$false" -Tag "NativeChecklist:whatif-confirm" {
        $splatWhatIf = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = $poolC
            WhatIf       = $true
        }
        @(Copy-DbaResourceGovernor @splatWhatIf).Count | Should -Be 0
        @(Get-NativeDestPool -Name $poolC).Count | Should -Be 0
        $splatConfirm = @{
            Source       = $TestConfig.InstanceCopy1
            Destination  = $TestConfig.InstanceCopy2
            ResourcePool = $poolC
            Confirm      = $false
        }
        $result = @(Copy-DbaResourceGovernor @splatConfirm)
        ($result | Where-Object Name -eq $poolC).Status | Should -BeExactly "Successful"
        @(Get-NativeDestPool -Name $poolC).grp | Should -Be $groupC
    }

    It "warns for a failed destination and continues with the next one" -Tag "NativeChecklist:multi-instance-failure" {
        $nativeWarnings = @()
        $splatContinue = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = @($nativeBadInstance, $TestConfig.InstanceCopy2)
            ResourcePool    = $poolC
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $result = @(Copy-DbaResourceGovernor @splatContinue)
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        ($result | Where-Object Name -eq $poolC).Status | Should -BeExactly "Skipped"
        @($result.DestinationServer | Select-Object -Unique) | Should -Be @($nativeDest.Name)
    }

    It "keeps earlier output before -EnableException stops at a failed destination, and stops at a failed source" -Tag "NativeChecklist:enable-exception" {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        try {
            Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2, $nativeBadInstance -ResourcePool $poolC -EnableException |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        @($nativeStreamed | Where-Object Name -eq $poolC).Count | Should -Be 1
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"

        $nativeWarnings = @()
        $splatBadSource = @{
            Source          = $nativeBadInstance
            Destination     = $TestConfig.InstanceCopy2
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaResourceGovernor @splatBadSource).Count | Should -Be 0
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        $nativeSourceCaught = $null
        try {
            $null = Copy-DbaResourceGovernor -Source $nativeBadInstance -Destination $TestConfig.InstanceCopy2 -EnableException
        } catch {
            $nativeSourceCaught = $PSItem
        }
        $nativeSourceCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "matches -ExcludeResourcePool and -ResourcePool values against pool names as PowerShell's -in does" {
        $poolNamesQuery = "SELECT name FROM sys.resource_governor_resource_pools"
        $destBefore = @((Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query $poolNamesQuery -EnableException).name)
        try {
            $excluded = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ExcludeResourcePool $numericValue)
            @($excluded | Where-Object Name -eq $poolNumeric).Count | Should -Be 0
            @($excluded | Where-Object Name -eq $poolA).Count | Should -Be 1
            @(Get-NativeDestPool -Name $poolNumeric).Count | Should -Be 0

            $included = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ResourcePool $numericValue)
            $includedPool = @($included | Where-Object Type -eq "Resource Governor Pool")
            $includedPool.Name | Should -BeExactly @($poolNumeric)
            $includedPool.Status | Should -BeExactly @("Successful")
            @(Get-NativeDestPool -Name $poolNumeric).grp | Should -Be $groupNumeric
        } finally {
            # The exclusion run copies every other user pool of the source; drop the ones it added beyond this file's.
            $ours = @($poolA, $poolB, $poolC, $poolNumeric)
            $destAfter = @((Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query $poolNamesQuery -EnableException).name)
            foreach ($added in $destAfter) {
                if ($added -notin $destBefore -and $added -notin $ours) {
                    $splatAdded = @{
                        SqlInstance     = $TestConfig.InstanceCopy2
                        Database        = "master"
                        Query           = "DECLARE @drop nvarchar(max) = N''; SELECT @drop += N'DROP WORKLOAD GROUP ' + QUOTENAME(g.name) + N'; ' FROM sys.resource_governor_workload_groups AS g INNER JOIN sys.resource_governor_resource_pools AS p ON p.pool_id = g.pool_id WHERE p.name = @pool; SELECT @drop += N'DROP RESOURCE POOL ' + QUOTENAME(@pool) + N';'; EXEC (@drop);"
                        SqlParameter    = @{ pool = $added }
                        EnableException = $true
                    }
                    Invoke-DbaQuery @splatAdded
                }
            }
        }
    }
}

Describe "Native Copy-DbaResourceGovernor governor state and classifier" -Tag IntegrationTests {
    BeforeAll {
        $nativeSuffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
        $noPool = "native_rg_none_$nativeSuffix"
        # A name that has to be quoted where it is spliced into ALTER RESOURCE GOVERNOR.
        $classifierName = "native rg-fn $nativeSuffix"
        $sourceEnabled = Get-NativeRgEnabled -Instance $TestConfig.InstanceCopy1
        $destEnabled = Get-NativeRgEnabled -Instance $TestConfig.InstanceCopy2
        $configQuery = "SELECT OBJECT_SCHEMA_NAME(classifier_function_id, 1) AS SchemaName, OBJECT_NAME(classifier_function_id, 1) AS FunctionName, is_enabled FROM sys.resource_governor_configuration"
        $clearClassifier = "IF EXISTS (SELECT 1 FROM sys.resource_governor_configuration WHERE classifier_function_id = OBJECT_ID(N'dbo.[$classifierName]')) BEGIN ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE; END; IF OBJECT_ID(N'dbo.[$classifierName]') IS NOT NULL DROP FUNCTION dbo.[$classifierName];"
    }

    AfterAll {
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            Invoke-DbaQuery -SqlInstance $instance -Database master -Query $clearClassifier -EnableException
        }
        Restore-NativeRgEnabled -Instance $TestConfig.InstanceCopy1 -Enabled $sourceEnabled
        Restore-NativeRgEnabled -Instance $TestConfig.InstanceCopy2 -Enabled $destEnabled
    }

    It "keeps the destination governor disabled when the source governor is disabled" {
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database master -Query "ALTER RESOURCE GOVERNOR RECONFIGURE; ALTER RESOURCE GOVERNOR DISABLE" -EnableException
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -EnableException
        $result = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ResourcePool $noPool)
        ($result | Where-Object Type -eq "Reconfigure Resource Governor").Status | Should -BeExactly "Successful"
        [bool](Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query $configQuery -EnableException).is_enabled | Should -BeFalse
    }

    It "copies, skips and with -Force overwrites a classifier function whose name needs quoting" {
        $splatSource = @{
            SqlInstance     = $TestConfig.InstanceCopy1
            Database        = "master"
            EnableException = $true
        }
        Invoke-DbaQuery @splatSource -Query "CREATE FUNCTION dbo.[$classifierName]() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'default' END"
        Invoke-DbaQuery @splatSource -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.[$classifierName]); ALTER RESOURCE GOVERNOR RECONFIGURE;"

        $created = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ResourcePool $noPool)
        @($created | Where-Object Status -eq "Failed").Count | Should -Be 0
        $classifierRow = @($created | Where-Object Name -eq "Classifier Function")
        $classifierRow.Status | Should -BeExactly "Successful"
        $classifierRow.Notes | Should -BeExactly "The new classifier function has been created"
        $config = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query $configQuery -EnableException
        $config.FunctionName | Should -BeExactly $classifierName

        $skipped = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ResourcePool $noPool)
        ($skipped | Where-Object Name -eq "Classifier Function").Notes | Should -BeExactly "Already exists on destination"

        $forced = @(Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ResourcePool $noPool -Force)
        @($forced | Where-Object Status -eq "Failed").Count | Should -Be 0
        ($forced | Where-Object Name -eq "Classifier Function").Notes | Should -BeExactly "The old classifier function has been overwritten."
        (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database master -Query $configQuery -EnableException).FunctionName | Should -BeExactly $classifierName
    }
}

Describe "Native Copy-DbaResourceGovernor refuses Azure SQL Database" -Tag IntegrationTests {
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

    It "warns that Azure SQL Database is not supported as the source and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            ResourcePool    = "native_rg_none"
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Copy-DbaResourceGovernor @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for an Azure SQL Database destination under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaResourceGovernor -Source $TestConfig.InstanceCopy1 -Destination $azureServer -ResourcePool "native_rg_none" -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
    }
}

Describe "Native Copy-DbaResourceGovernor over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginPool = "native_rg_login_$([Guid]::NewGuid().ToString('N'))"
        }

        # Source and destination are the same shared instance; -WhatIf keeps its governor untouched, and the verbose
        # "Migrating pools." is written only after both connects and the classifier lookups succeeded.
        It "works with the source and destination credentials" {
            $loginWarnings = @()
            $splatLogin = @{
                Source                   = $loginInstance
                SourceSqlCredential      = $loginCred
                Destination              = $loginInstance
                DestinationSqlCredential = $loginCred
                ResourcePool             = $loginPool
                WhatIf                   = $true
                Verbose                  = $true
                EnableException          = $true
                WarningVariable          = "loginWarnings"
            }
            $loginStreams = @(Copy-DbaResourceGovernor @splatLogin 4>&1)
            @($loginStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Migrating pools.*" }).Count | Should -Be 1
            @($loginStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            $loginWarnings.Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                Source          = $loginInstance
                Destination     = $loginInstance
                ResourcePool    = $loginPool
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            @(Copy-DbaResourceGovernor @splatLoginNoCredential).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Copy-DbaResourceGovernor -Source $loginInstance -Destination $loginInstance -ResourcePool $loginPool -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
