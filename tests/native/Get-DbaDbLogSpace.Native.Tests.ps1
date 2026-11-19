#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbLogSpace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads log space.
# NativeSkip: Calculation for space used should work for servers < 2012 -- covered: Native Get-DbaDbLogSpace.An instance older than SQL Server 2012.reports the used space as its share of the log size

Describe "Native Get-DbaDbLogSpace" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique per leg and run: the legs of one SQL version share the instance. No test reads every database.
        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance
        $mainDb = "dbatoolsci_nls_$random"
        $secondDb = "dbatoolsci_nls2_$random"
        $offlineDb = "dbatoolsci_nlsoff_$random"
        $snapshotDb = "dbatoolsci_nlssnap_$random"

        $dataPath = [string]$server.ConnectionContext.ExecuteScalar("SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(512));")
        $null = $server.Query("CREATE DATABASE [$mainDb];")
        $null = $server.Query("ALTER DATABASE [$mainDb] MODIFY FILE (NAME = N'$($mainDb)_log', SIZE = 10MB);")
        foreach ($name in $secondDb, $offlineDb) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $null = $server.Query("CREATE DATABASE [$snapshotDb] ON (NAME = N'$mainDb', FILENAME = N'$($dataPath.TrimEnd('\'))\$snapshotDb.ss') AS SNAPSHOT OF [$mainDb];")
        $null = $server.Query("ALTER DATABASE [$offlineDb] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = $server.Query("IF DB_ID(N'$offlineDb') IS NOT NULL ALTER DATABASE [$offlineDb] SET ONLINE;")
        $null = $server.Query("IF DB_ID(N'$snapshotDb') IS NOT NULL DROP DATABASE [$snapshotDb];")
        foreach ($name in $mainDb, $secondDb, $offlineDb) {
            $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns a plain object with the pinned properties in their order" {
            $result = Get-DbaDbLogSpace -SqlInstance $instance -Database $mainDb
            $result.PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result.PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "LogSize", "LogSpaceUsedPercent", "LogSpaceUsed")
            $result.Database | Should -BeExactly $mainDb
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.LogSize | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
            $result.LogSpaceUsed | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
            $result.LogSpaceUsedPercent | Should -BeOfType [single]
        }

        It "reports the values sys.dm_db_log_space_usage holds" {
            $before = @($server.Query("SELECT * FROM sys.dm_db_log_space_usage", $mainDb))
            $result = Get-DbaDbLogSpace -SqlInstance $instance -Database $mainDb
            $after = @($server.Query("SELECT * FROM sys.dm_db_log_space_usage", $mainDb))
            $used = @($before[0].used_log_space_in_bytes, $after[0].used_log_space_in_bytes) | Sort-Object
            $result.LogSize.Byte | Should -Be $before[0].total_log_size_in_bytes
            $result.LogSpaceUsed.Byte | Should -BeGreaterOrEqual $used[0]
            $result.LogSpaceUsed.Byte | Should -BeLessOrEqual $used[1]
        }

        It "leaves the values of a database snapshot empty, since a snapshot has no log" {
            $result = Get-DbaDbLogSpace -SqlInstance $instance -Database $snapshotDb -WarningVariable warnings
            $warnings | Should -BeNullOrEmpty
            $result.Database | Should -BeExactly $snapshotDb
            $result.LogSize | Should -BeNullOrEmpty
            $result.LogSpaceUsedPercent | Should -BeNullOrEmpty
            $result.LogSpaceUsed | Should -BeNullOrEmpty
        }
    }

    Context "Selection" {
        It "matches -Database without regard to case and reads each name once" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database $secondDb.ToUpperInvariant(), $mainDb)
            @($result.Database | Sort-Object) | Should -BeExactly @($secondDb, $mainDb | Sort-Object)
        }

        It "reads nothing for a name that does not exist" {
            $result = Get-DbaDbLogSpace -SqlInstance $instance -Database "dbatoolsci_nlsabsent_$random" -WarningVariable warnings
            $result | Should -BeNullOrEmpty
            $warnings | Should -BeNullOrEmpty
        }

        It "selects nothing with two empty names, which are a filter where one is not" {
            @(Get-DbaDbLogSpace -SqlInstance $instance -Database "", "").Count | Should -Be 0
        }

        It "expands a wildcard in -Database" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database "dbatoolsci_nls?_$random", "DBATOOLSCI_NLS_*$random")
            @($result.Database | Sort-Object) | Should -BeExactly @($secondDb, $mainDb | Sort-Object)
        }

        It "expands a wildcard in -ExcludeDatabase" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database $mainDb, $secondDb -ExcludeDatabase "dbatoolsci_nls2_?*")
            $result.Database | Should -BeExactly $mainDb
        }

        It "leaves out a database named in -ExcludeDatabase" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database $mainDb, $secondDb -ExcludeDatabase $secondDb)
            $result.Database | Should -BeExactly $mainDb
        }

        It "leaves out system databases, and keeps them under -ExcludeSystemDatabase:`$false" -Tag "NativeChecklist:switch-false" {
            $excluded = @(Get-DbaDbLogSpace -SqlInstance $instance -Database master, $mainDb -ExcludeSystemDatabase)
            $excluded.Database | Should -BeExactly $mainDb
            $kept = @(Get-DbaDbLogSpace -SqlInstance $instance -Database master, $mainDb -ExcludeSystemDatabase:$false)
            $kept.Database | Should -Contain "master"
            $kept.Database | Should -Contain $mainDb
        }
    }

    Context "A database that cannot be opened" {
        BeforeAll {
            $skipText = "Skipping [$offlineDb] on $instance because it is not accessible, so its log space cannot be read"
        }

        It "warns of it by name and reads the others" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database $offlineDb, $mainDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Database | Should -BeExactly $mainDb
            @($warnings).Count | Should -Be 1
            "$warnings".Contains($skipText) | Should -BeTrue
        }

        It "stays a warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $result = Get-DbaDbLogSpace -SqlInstance $instance -Database $offlineDb -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$warnings".Contains($skipText) | Should -BeTrue
        }

        It "says nothing of it once it is excluded" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $instance -Database $offlineDb, $mainDb -ExcludeDatabase $offlineDb -WarningVariable warnings)
            $result.Database | Should -BeExactly $mainDb
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context "An instance older than SQL Server 2012" {
        BeforeAll {
            # The lab has no such instance. A connection told an older version before it opens takes the DBCC path on a real instance.
            $olderConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $instance
            $olderConnection.TrustServerCertificate = $true
            $olderConnection.ServerVersion = New-Object Microsoft.SqlServer.Management.Common.ServerVersion -ArgumentList 10, 50, 6000
            $olderServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $olderConnection
            $olderResult = Get-DbaDbLogSpace -SqlInstance $olderServer -Database $mainDb
        }

        It "reports the used space as its share of the log size" {
            $olderResult | Should -Not -BeNullOrEmpty
            $olderResult.LogSpaceUsed | Should -Be ($olderResult.LogSize * ($olderResult.LogSpaceUsedPercent / 100))
        }

        It "reads the size and the percentage from DBCC SQLPERF(LOGSPACE)" {
            $olderResult.PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "LogSize", "LogSpaceUsedPercent", "LogSpaceUsed")
            $olderResult.Database | Should -BeExactly $mainDb
            $olderResult.LogSize.Kilobyte | Should -BeExactly 10232
            $olderResult.LogSpaceUsedPercent | Should -BeOfType [single]
            $olderResult.LogSpaceUsedPercent | Should -BeGreaterThan 0
        }

        It "keeps only the selected databases of that one report" {
            $result = @(Get-DbaDbLogSpace -SqlInstance $olderServer -Database $offlineDb, $secondDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Database | Should -BeExactly $secondDb
            "$warnings".Contains("Skipping [$offlineDb]") | Should -BeTrue
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $result = @($instance, $instance | Get-DbaDbLogSpace -Database $mainDb)
            $result.Count | Should -Be 2
            $result.Database | Should -BeExactly @($mainDb, $mainDb)
        }

        It "warns of a failed instance and goes on, and throws it under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbLogSpace -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Database | Should -BeExactly $mainDb
            "$warnings" | Should -BeLike "*Failure | *refused*"

            { Get-DbaDbLogSpace -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException } | Should -Throw -ExpectedMessage "*refused*" -ErrorId "dbatools_Get-DbaDbLogSpace*"
        }
    }
}

Describe "Native Get-DbaDbLogSpace on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    It "reads a database through a connection to it" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = Get-DbaDbLogSpace -SqlInstance $azureServer -Database $azureDatabase
        $result.Database | Should -BeExactly $azureDatabase
        $result.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result.LogSize.Byte | Should -BeGreaterThan 0
        $result.LogSpaceUsedPercent | Should -BeOfType [single]
    }

    It "reads the database and master from a connection of its own to the logical server" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbLogSpace -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings)
        $warnings | Should -BeNullOrEmpty
        $result.Database | Should -Contain $azureDatabase
        $result.Database | Should -Contain "master"
    }

    # The connection sees one database, so a bound filter here reads no other lane's work and no long list.
    It "treats an empty -Database as no filter and two empty names as a filter" -Tag "NativeChecklist:azure-sqldb" {
        (Get-DbaDbLogSpace -SqlInstance $azureServer -Database @()).Database | Should -BeExactly $azureDatabase
        (Get-DbaDbLogSpace -SqlInstance $azureServer -Database $null).Database | Should -BeExactly $azureDatabase
        (Get-DbaDbLogSpace -SqlInstance $azureServer -Database "").Database | Should -BeExactly $azureDatabase
        @(Get-DbaDbLogSpace -SqlInstance $azureServer -Database "", "").Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbLogSpace over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique names and cleanup: every leg uses this one shared instance.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $random = Get-Random
        $loginDb = "dbatoolsci_nlslogin_$random"
        $lowName = "dbatoolsci_nlslow_$random"
        $lowPassword = "Nls-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)

        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred
        $null = $loginServer.Query("CREATE DATABASE [$loginDb];")
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $null = $loginServer.Databases[$loginDb].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName];")
        $loginServer.Databases.Refresh()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("USE [master]; IF DB_ID(N'$loginDb') IS NOT NULL BEGIN ALTER DATABASE [$loginDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$loginDb]; END;")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = Get-DbaDbLogSpace -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDb -EnableException
            $result.Database | Should -BeExactly $loginDb
            $result.LogSize.Byte | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbLogSpace -SqlInstance $loginInstance -Database $loginDb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*Login failed*"
        }

        # As the pin measured: the connection is the command's own, so the failure throws.
        It "throws the connection failure under -EnableException, as the pinned function does" {
            { Get-DbaDbLogSpace -SqlInstance $loginInstance -Database $loginDb -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbLogSpace*"
        }
    }

    Context "A login that may not read the view" {
        It "warns of each database and goes on" -Tag "NativeChecklist:enable-exception" {
            $result = Get-DbaDbLogSpace -SqlInstance $loginInstance -SqlCredential $lowCred -Database $loginDb, master -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 2
            "$($warnings[0])" | Should -BeLike "*Unable to collect log space data on $loginInstance. | Execute with results failed for Database *permission was denied*"
            "$($warnings[1])" | Should -BeLike "*Unable to collect log space data on $loginInstance. | Execute with results failed for Database *permission was denied*"
        }

        It "throws the failed read under -EnableException, with the database as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbLogSpace -SqlInstance $loginInstance -SqlCredential $lowCred -Database $loginDb -EnableException
            } catch {
                $record = $PSItem
            }
            $record | Should -Not -BeNullOrEmpty
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbLogSpace*"
            $record.Exception.Message | Should -BeLike "Execute with results failed for Database '$loginDb'. An exception occurred while executing a Transact-SQL statement or batch.*permission was denied*"
            $record.Exception.InnerException | Should -BeOfType [System.Management.Automation.MethodInvocationException]
            $record.TargetObject.Name | Should -BeExactly $loginDb
        }

        It "warns once when the DBCC of an older instance is refused, and reads nothing" {
            $olderConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $loginInstance, $lowName, $lowPassword
            $olderConnection.TrustServerCertificate = $true
            $olderConnection.ServerVersion = New-Object Microsoft.SqlServer.Management.Common.ServerVersion -ArgumentList 10, 50, 6000
            $olderServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $olderConnection
            $result = Get-DbaDbLogSpace -SqlInstance $olderServer -Database $loginDb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$warnings" | Should -BeLike "*Unable to collect log space data on *. | *"
        }
    }
}
