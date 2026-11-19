#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMemoryUsage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the buffer pool.

Describe "Native Get-DbaDbMemoryUsage" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique per leg and run. Two quiet databases hold pages of their own, so no test depends on what else the instance caches.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance
        $random = Get-Random
        $mainDb = "dbatoolsci_nmu_$random"
        $secondDb = "dbatoolsci_nmu2_$random"
        foreach ($name in $mainDb, $secondDb) {
            $null = $server.Query("CREATE DATABASE [$name];")
            $null = $server.Query("SELECT TOP (4000) a.name, a.object_id INTO dbo.filler FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;", $name)
            $null = $server.Query("SELECT COUNT(*) AS rows_read FROM dbo.filler;", $name)
        }
        $systemNames = @("master", "model", "msdb", "tempdb", "ResourceDb")

        # The page counts of a database by page type, from the view itself.
        function Get-NativePageCount ($Name) {
            $counts = @{ }
            foreach ($row in $server.Query("SELECT page_type, COUNT_BIG(*) AS pages FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID(N'$Name') GROUP BY page_type;")) {
                $counts[$row.page_type] = [long]$row.pages
            }
            $counts
        }
        function Format-NativePageCount ($Counts) {
            ($Counts.Keys | Sort-Object | ForEach-Object { "$PSItem=$($Counts[$PSItem])" }) -join ","
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $mainDb, $secondDb) {
            $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns plain objects with the pinned properties in their order, PageCount left out of the default view" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb)
            $result.Count | Should -BeGreaterThan 0
            foreach ($row in $result) {
                $row.PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
                $row.PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "PageType", "PageCount", "Size", "PercentUsed")
                $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "Database", "InstanceName", "PageType", "PercentUsed", "Size", "SqlInstance")
                $row.ComputerName | Should -BeExactly $server.ComputerName
                $row.InstanceName | Should -BeExactly $server.ServiceName
                $row.SqlInstance | Should -BeExactly $server.DomainInstanceName
                $row.Database | Should -BeExactly $mainDb
                $row.PageType | Should -BeOfType [string]
                $row.PageCount | Should -BeOfType [int]
                $row.Size | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
                $row.PercentUsed | Should -BeOfType [double]
            }
        }

        It "orders the rows by database name" {
            # A database being dropped elsewhere on the instance has pages and no name for a moment.
            $names = @((Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb).Database | Where-Object { $PSItem -is [string] } | Select-Object -Unique)
            $literals = @($names | ForEach-Object { "(N'" + $PSItem.Replace("'", "''") + "')" })
            $sorted = @($server.Query("SELECT name FROM (VALUES $($literals -join ',')) AS d(name) ORDER BY name;").name)
            $names | Should -BeExactly $sorted
        }

        It "reports the pages the view holds for each page type" {
            # The cache can change under any read, so a pass needs the same counts on both sides of the command.
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $expected = Get-NativePageCount -Name $mainDb
                $result = @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb)
                $again = Get-NativePageCount -Name $mainDb
                if ((Format-NativePageCount -Counts $expected) -eq (Format-NativePageCount -Counts $again)) {
                    break
                }
            }
            $result.Count | Should -Be $expected.Count
            foreach ($row in $result) {
                $row.PageCount | Should -Be $expected[$row.PageType]
            }
        }

        It "reports each row's size as its pages" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb, master -IncludeSystemDb)
            $result.Count | Should -BeGreaterThan 0
            foreach ($row in $result) {
                $row.Size.Byte | Should -Be ([long]$row.PageCount * 8192)
            }
        }

        It "rounds the share of the buffer pool to a whole number" {
            foreach ($row in Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb) {
                $row.PercentUsed | Should -Be ([Math]::Round($row.PercentUsed))
                $row.PercentUsed | Should -BeGreaterOrEqual 0
            }
        }
    }

    Context "Filters" {
        It "leaves out the system databases, and keeps them under -IncludeSystemDb" {
            $names = @((Get-DbaDbMemoryUsage -SqlInstance $instance).Database | Select-Object -Unique)
            $names | Should -Contain $mainDb
            foreach ($name in $systemNames) {
                $names | Should -Not -Contain $name
            }
            $withSystem = @((Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb).Database | Select-Object -Unique)
            $withSystem | Should -Contain $mainDb
            $withSystem | Should -Contain "master"
            $withSystem | Should -Contain "ResourceDb"
        }

        It "leaves out the system databases when -IncludeSystemDb is passed as false" -Tag "NativeChecklist:switch-false" {
            $names = @((Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb:$false).Database | Select-Object -Unique)
            $names | Should -Contain $mainDb
            foreach ($name in $systemNames) {
                $names | Should -Not -Contain $name
            }
        }

        It "selects -Database by name, ignoring case" {
            @((Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb).Database | Select-Object -Unique) | Should -BeExactly @($mainDb)
            @((Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb.ToUpperInvariant()).Database | Select-Object -Unique) | Should -BeExactly @($mainDb)
            @((Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb, $secondDb).Database | Select-Object -Unique | Sort-Object) | Should -BeExactly @($mainDb, $secondDb | Sort-Object)
        }

        It "honours a wildcard in -Database" {
            @((Get-DbaDbMemoryUsage -SqlInstance $instance -Database "dbatoolsci_nmu*_$random").Database | Select-Object -Unique | Sort-Object) | Should -BeExactly @($mainDb, $secondDb | Sort-Object)
            @((Get-DbaDbMemoryUsage -SqlInstance $instance -Database "DBATOOLSCI_NMU?_$random").Database | Select-Object -Unique) | Should -BeExactly @($secondDb)
        }

        It "still drops a system database that -Database selects, without -IncludeSystemDb" {
            @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database master).Count | Should -Be 0
        }

        It "selects nothing with a -Database that is bound and empty" {
            @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database $null).Count | Should -Be 0
            @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database @()).Count | Should -Be 0
        }

        It "excludes -ExcludeDatabase by exact name, ignoring case" {
            $names = @((Get-DbaDbMemoryUsage -SqlInstance $instance -ExcludeDatabase $mainDb.ToUpperInvariant()).Database | Select-Object -Unique)
            $names | Should -Not -Contain $mainDb
            $names | Should -Contain $secondDb
            $patterned = @((Get-DbaDbMemoryUsage -SqlInstance $instance -ExcludeDatabase "dbatoolsci_nmu*").Database | Select-Object -Unique)
            $patterned | Should -Contain $mainDb
        }

        It "lets -ExcludeDatabase win over -Database" {
            @(Get-DbaDbMemoryUsage -SqlInstance $instance -Database $mainDb -ExcludeDatabase $mainDb).Count | Should -Be 0
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $result = @($instance, $instance | Get-DbaDbMemoryUsage -Database $mainDb)
            @($result | Group-Object Database, PageType | Where-Object Count -eq 2).Count | Should -BeGreaterThan 0
        }

        It "takes -Database from a property of the piped instance" {
            # The instance parameter converts no custom object, so the property sits on the name itself.
            $piped = "$instance" | Add-Member -NotePropertyName Database -NotePropertyValue $mainDb -PassThru
            @(($piped | Get-DbaDbMemoryUsage).Database | Select-Object -Unique) | Should -BeExactly @($mainDb)
        }

        It "warns of a failed instance and goes on, and throws it under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result.Database | Select-Object -Unique) | Should -BeExactly @($mainDb)
            "$warnings" | Should -BeLike "*Failure | *refused*"

            { Get-DbaDbMemoryUsage -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException } | Should -Throw -ExpectedMessage "*refused*" -ErrorId "dbatools_Get-DbaDbMemoryUsage*"
        }
    }
}

Describe "Native Get-DbaDbMemoryUsage over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique names and cleanup: every leg uses this one shared instance. A public login may not read the views.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $random = Get-Random
        $lowName = "dbatoolsci_nmulow_$random"
        $viewName = "dbatoolsci_nmuview_$random"
        $lowPassword = "Nmu-$([guid]::NewGuid().ToString('N'))"
        $lowSecure = ConvertTo-SecureString -String $lowPassword -AsPlainText -Force
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, $lowSecure
        $viewCred = New-Object System.Management.Automation.PSCredential -ArgumentList $viewName, $lowSecure

        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred
        foreach ($name in $lowName, $viewName) {
            $null = $loginServer.Query("CREATE LOGIN [$name] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        }
        $null = $loginServer.Query("GRANT VIEW SERVER STATE TO [$viewName]; DENY VIEW ANY DATABASE TO [$viewName];", "master")
        $lowServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred
        $viewServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $viewCred

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $lowName, $viewName) {
            $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$name'; EXEC sys.sp_executesql @kill;")
            $null = $loginServer.Query("IF SUSER_ID(N'$name') IS NOT NULL DROP LOGIN [$name];")
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $loginInstance -SqlCredential $loginCred -Database master -IncludeSystemDb -EnableException)
            $result.Count | Should -BeGreaterThan 0
            @($result.Database | Select-Object -Unique) | Should -BeExactly @("master")
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $loginInstance -IncludeSystemDb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*Login failed*"
        }

        It "throws the connection failure under -EnableException, as the pinned function does" {
            { Get-DbaDbMemoryUsage -SqlInstance $loginInstance -IncludeSystemDb -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbMemoryUsage*"
        }
    }

    Context "A login that may not read the views" {
        It "warns that the read failed and returns nothing" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $lowServer -IncludeSystemDb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$warnings" | Should -BeLike "*Issue collecting data | An exception occurred while executing a Transact-SQL statement or batch.*VIEW SERVER*permission was denied*"
        }

        It "goes on to the next instance after a failed read" -Tag "NativeChecklist:multi-instance-failure" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $lowServer, $loginServer -Database master -IncludeSystemDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
        }

        # Stop-Function only warns here, and a warning is no error for -ErrorAction, as on the pin.
        It "goes on to the next instance under -ErrorAction Stop too" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $lowServer, $loginServer -Database master -IncludeSystemDb -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
        }

        # One row per database and page type: a row seen twice was written for the instance that failed.
        It "reports nothing for an instance whose read failed after one that worked" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $loginServer, $lowServer -Database master -IncludeSystemDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -BeGreaterThan 0
            @($result | Group-Object Database, PageType | Where-Object Count -ne 1).Count | Should -Be 0
            @($warnings).Count | Should -Be 1
        }

        It "reports nothing for a piped instance whose read failed after one that worked" {
            $result = @($loginServer, $lowServer | Get-DbaDbMemoryUsage -Database master -IncludeSystemDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -BeGreaterThan 0
            @($result | Group-Object Database, PageType | Where-Object Count -ne 1).Count | Should -Be 0
            @($warnings).Count | Should -Be 1
        }

        It "throws the failed read under -EnableException, keeping the rows already written" -Tag "NativeChecklist:enable-exception" {
            $seen = New-Object System.Collections.ArrayList
            $record = $null
            try {
                Get-DbaDbMemoryUsage -SqlInstance $loginServer, $lowServer -Database master -IncludeSystemDb -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $record = $PSItem
            }
            $record | Should -Not -BeNullOrEmpty
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMemoryUsage*"
            $record.CategoryInfo.Category | Should -Be "NotSpecified"
            $record.Exception.Message | Should -BeLike "An exception occurred while executing a Transact-SQL statement or batch.*VIEW SERVER*permission was denied*"
            $chain = @(for ($failure = $record.Exception; $null -ne $failure; $failure = $failure.InnerException) { $failure.GetType().FullName })
            $chain | Should -BeExactly @("System.Exception", "System.Management.Automation.MethodInvocationException", "System.Management.Automation.RuntimeException", "System.Management.Automation.RuntimeException")
            $record.Exception.InnerException.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s): "An exception occurred*'
            "$($record.TargetObject)" | Should -BeLike "$loginInstance*"
            $seen.Count | Should -BeGreaterThan 0
        }
    }

    Context "A login that may read the views but not see the databases" {
        It "keeps the rows of the databases it cannot name, as the engine gives them" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $viewServer)
            @($result | Where-Object { $PSItem.Database -is [System.DBNull] }).Count | Should -BeGreaterThan 0
        }

        It "drops those rows under -Database" {
            $result = @(Get-DbaDbMemoryUsage -SqlInstance $viewServer -Database master -IncludeSystemDb)
            $result.Count | Should -BeGreaterThan 0
            @($result.Database | Select-Object -Unique) | Should -BeExactly @("master")
        }

        It "compares a hidden name with -Database as the pin does: a null value or a pattern leaves it out, an empty string keeps it" {
            $withNull = @(Get-DbaDbMemoryUsage -SqlInstance $viewServer -Database @("master", $null) -IncludeSystemDb)
            $withNull.Count | Should -BeGreaterThan 0
            @($withNull | Where-Object { $PSItem.Database -is [System.DBNull] }).Count | Should -Be 0
            @($withNull | Where-Object { $PSItem.Database -eq "master" }).Count | Should -Be $withNull.Count

            $withPattern = @(Get-DbaDbMemoryUsage -SqlInstance $viewServer -Database "*" -IncludeSystemDb)
            @($withPattern | Where-Object { $PSItem.Database -eq "master" }).Count | Should -BeGreaterThan 0
            @($withPattern | Where-Object { $PSItem.Database -is [System.DBNull] }).Count | Should -Be 0

            $withEmpty = @(Get-DbaDbMemoryUsage -SqlInstance $viewServer -Database @("master", "") -IncludeSystemDb)
            @($withEmpty | Where-Object { $PSItem.Database -is [System.DBNull] }).Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Native Get-DbaDbMemoryUsage on Azure SQL Database" -Tag IntegrationTests {
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
        # A database that just resumed has an empty cache, so this read puts pages of its own there.
        $null = $azureServer.Query("SELECT COUNT(*) AS objects_read FROM sys.objects;")
    }

    It "reads the buffer pool through a connection to the database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = @(Get-DbaDbMemoryUsage -SqlInstance $azureServer -Database $azureDatabase -EnableException)
        $result.Count | Should -BeGreaterThan 0
        foreach ($row in $result) {
            $row.Database | Should -BeExactly $azureDatabase
            $row.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $row.ComputerName | Should -BeExactly $azureServer.ComputerName
            $row.Size | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
            $row.PercentUsed | Should -BeOfType [double]
        }
    }

    It "reports each row's size as its pages on Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbMemoryUsage -SqlInstance $azureServer -Database $azureDatabase -EnableException)
        $result.Count | Should -BeGreaterThan 0
        foreach ($row in $result) {
            $row.Size.Byte | Should -Be ([long]$row.PageCount * 8192)
        }
    }

    It "leaves out the system databases, and keeps them under -IncludeSystemDb" -Tag "NativeChecklist:azure-sqldb" {
        $names = @((Get-DbaDbMemoryUsage -SqlInstance $azureServer -EnableException).Database | Select-Object -Unique)
        $names | Should -Contain $azureDatabase
        $names | Should -Not -Contain "master"
        $withSystem = @((Get-DbaDbMemoryUsage -SqlInstance $azureServer -IncludeSystemDb -EnableException).Database | Select-Object -Unique)
        $withSystem | Should -Contain $azureDatabase
        $withSystem | Should -Contain "master"
    }
}
