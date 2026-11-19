#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbIdentity",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaDbIdentity" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique per leg and run: the legs of one SQL version share the instance. No test reads every database.
        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance
        $mainDb = "dbatoolsci_nid_$random"
        $secondDb = "dbatoolsci_nid2_$random"
        $offlineDb = "dbatoolsci_nidoff_$random"
        $injected = "dbatoolsci_nidinjected_$random"
        # Two characters no Latin1 code page holds; [char] keeps this file ASCII for Windows PowerShell.
        $outsideName = "id" + [char]0x8868 + [char]0x0416

        $null = $server.Query("CREATE DATABASE [$mainDb] COLLATE Latin1_General_CI_AS;")
        foreach ($name in $secondDb, $offlineDb) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $fixture = @(
            "CREATE TABLE dbo.[$outsideName] (Id int NOT NULL IDENTITY (31, 1), Value varchar(5)); INSERT INTO dbo.[$outsideName] (Value) SELECT '1';",
            "CREATE TABLE dbo.idmain (Id int NOT NULL IDENTITY (125, 1), Value varchar(5)); INSERT INTO dbo.idmain (Value) SELECT '1';",
            "CREATE TABLE dbo.idgap (Id int NOT NULL IDENTITY (1, 1), Value varchar(5)); INSERT INTO dbo.idgap (Value) SELECT '1' UNION ALL SELECT '2'; DELETE FROM dbo.idgap WHERE Id = 2;",
            "CREATE TABLE dbo.idempty (Id int NOT NULL IDENTITY (1, 1), Value varchar(5));",
            "CREATE TABLE dbo.idneg (Id int NOT NULL IDENTITY (-5, -1), Value varchar(5)); INSERT INTO dbo.idneg (Value) SELECT '1';",
            "CREATE TABLE dbo.idbig (Id bigint NOT NULL IDENTITY (5000000000, 1), Value varchar(5)); INSERT INTO dbo.idbig (Value) SELECT '1';",
            "CREATE TABLE dbo.noident (Id int NOT NULL);",
            "CREATE TABLE dbo.[Bad]]Name] (Id int NOT NULL IDENTITY (11, 1), Value varchar(5)); INSERT INTO dbo.[Bad]]Name] (Value) SELECT '1';",
            "CREATE TABLE dbo.[Quote'Name] (Id int NOT NULL IDENTITY (12, 1), Value varchar(5)); INSERT INTO dbo.[Quote'Name] (Value) SELECT '1';",
            "CREATE TABLE dbo.[Space Name] (Id int NOT NULL IDENTITY (13, 1), Value varchar(5)); INSERT INTO dbo.[Space Name] (Value) SELECT '1';",
            "CREATE TABLE dbo.[Dot.Name] (Id int NOT NULL IDENTITY (14, 1), Value varchar(5)); INSERT INTO dbo.[Dot.Name] (Value) SELECT '1';"
        )
        foreach ($statement in $fixture) {
            $null = $server.Query($statement, $mainDb)
        }
        $null = $server.Query("CREATE SCHEMA probe;", $mainDb)
        $null = $server.Query("CREATE TABLE probe.idmain (Id int NOT NULL IDENTITY (21, 1), Value varchar(5)); INSERT INTO probe.idmain (Value) SELECT '1';", $mainDb)
        $null = $server.Query("CREATE TABLE dbo.idmain (Id int NOT NULL IDENTITY (7, 1), Value varchar(5)); INSERT INTO dbo.idmain (Value) SELECT '1';", $secondDb)
        $null = $server.Query("ALTER DATABASE [$offlineDb] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # A session of its own in master: DROP DATABASE refuses a database a session sits in.
        $cleanup = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        $null = $cleanup.Query("IF DB_ID(N'$offlineDb') IS NOT NULL ALTER DATABASE [$offlineDb] SET ONLINE;")
        foreach ($name in $mainDb, $secondDb, $offlineDb) {
            $null = $cleanup.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $cleanup.ConnectionContext.Disconnect()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns the pinned properties, in order, on a plain object" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idmain)
            $result.Count | Should -Be 1
            ($result[0].PSObject.Properties.Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Database,Table,Cmd,IdentityValue,ColumnValue,Output"
            $result[0].PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
            $result[0].ComputerName | Should -Be $server.ComputerName
            $result[0].InstanceName | Should -Be $server.ServiceName
            $result[0].SqlInstance | Should -Be $server.DomainInstanceName
            $result[0].Database | Should -Be $mainDb
            $result[0].Table | Should -BeExactly "dbo.idmain"
            $result[0].Cmd | Should -BeExactly "DBCC CHECKIDENT('[dbo].[idmain]', NORESEED)"
        }

        It "reports the two values as text and every line DBCC printed" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idmain
            $result.IdentityValue | Should -BeOfType [string]
            $result.IdentityValue | Should -BeExactly "125"
            $result.ColumnValue | Should -BeOfType [string]
            $result.ColumnValue | Should -BeExactly "125"
            $result.PSObject.Properties["Output"].TypeNameOfValue | Should -Be "System.Object[]"
            ($result.Output -join "|") | Should -BeExactly "Checking identity information: current identity value '125', current column value '125'.|DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "reports a gap, an empty table, a negative value and a big value as DBCC does" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idgap, dbo.idempty, dbo.idneg, dbo.idbig)
            (@($result.IdentityValue) -join ",") | Should -BeExactly "2,NULL,-5,5000000000"
            (@($result.ColumnValue) -join ",") | Should -BeExactly "1,NULL,-5,5000000000"
        }
    }

    Context "Table names" {
        It "escapes a closing bracket in a table name" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table "[dbo].[Bad]]Name]"
            $result.Table | Should -BeExactly "[dbo].[Bad]]Name]"
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT('[dbo].[Bad]]Name]', NORESEED)"
            $result.IdentityValue | Should -BeExactly "11"
        }

        It "brackets the name and schema it splits, and leaves the database part out" {
            $expected = @(
                @{ Table = "idmain"; Cmd = "DBCC CHECKIDENT('[idmain]', NORESEED)"; Value = "125" },
                @{ Table = "probe.idmain"; Cmd = "DBCC CHECKIDENT('[probe].[idmain]', NORESEED)"; Value = "21" },
                @{ Table = "dbo.Space Name"; Cmd = "DBCC CHECKIDENT('[dbo].[Space Name]', NORESEED)"; Value = "13" },
                @{ Table = "dbo.[Dot.Name]"; Cmd = "DBCC CHECKIDENT('[dbo].[Dot.Name]', NORESEED)"; Value = "14" },
                @{ Table = "$mainDb.dbo.idmain"; Cmd = "DBCC CHECKIDENT('[dbo].[idmain]', NORESEED)"; Value = "125" },
                @{ Table = "$mainDb..idmain"; Cmd = "DBCC CHECKIDENT('[idmain]', NORESEED)"; Value = "125" }
            )
            foreach ($case in $expected) {
                $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table $case.Table
                $result.Table | Should -BeExactly $case.Table
                $result.Cmd | Should -BeExactly $case.Cmd
                $result.IdentityValue | Should -BeExactly $case.Value
            }
        }

        It "passes a name it cannot split through as written" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table "a.b.c.d" -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT('a.b.c.d', NORESEED)"
            ($warnings -join " ") | Should -BeLike "*four-part name*"
        }

        It "reads a table whose name holds a single quote" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table "dbo.[Quote'Name]"
            $result.Table | Should -BeExactly "dbo.[Quote'Name]"
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT('[dbo].[Quote''Name]', NORESEED)"
            $result.IdentityValue | Should -BeExactly "12"
        }

        It "keeps a single quote inside the DBCC string, so nothing after it runs" {
            $hostile = "x', NORESEED); CREATE TABLE $injected (a int); --"
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table $hostile -WarningVariable warnings -WarningAction SilentlyContinue
            @($server.Query("SELECT name FROM sys.tables WHERE name = N'$injected';", $mainDb)).Count | Should -Be 0
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT('[x'', NORESEED); CREATE TABLE $injected (a int); --]', NORESEED)"
            $result.IdentityValue | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Cannot find a table or object with the name*"
        }

        It "keeps a single quote inside the DBCC string for a name it cannot split" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table "a.b.c.d'e" -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT('a.b.c.d''e', NORESEED)"
            ($warnings -join " ") | Should -Not -BeLike "*Incorrect syntax*"
        }

        It "reads a table whose name lies outside the code page of the database" {
            $result = Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table "dbo.$outsideName"
            $result.Table | Should -BeExactly "dbo.$outsideName"
            $result.Cmd | Should -BeExactly "DBCC CHECKIDENT(N'[dbo].[$outsideName]', NORESEED)"
            $result.IdentityValue | Should -BeExactly "31"
        }
    }

    Context "Selection" {
        It "matches -Database in any case" {
            (Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb.ToUpperInvariant() -Table dbo.idmain).Database | Should -Be $mainDb
        }

        It "reads the table in each named database" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $secondDb, $mainDb -Table dbo.idmain)
            $result.Count | Should -Be 2
            ($result | Where-Object Database -eq $mainDb).IdentityValue | Should -BeExactly "125"
            ($result | Where-Object Database -eq $secondDb).IdentityValue | Should -BeExactly "7"
        }

        It "returns nothing and warns of nothing for a database that does not exist" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database "dbatoolsci_nosuch_$random" -Table dbo.idmain -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
        }

        It "returns nothing for a null or empty -Table" {
            @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table $null -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
            @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table @() -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
        }

        It "reads a null element of -Table as an empty name and goes on" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table @($null, "dbo.idmain") -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 2
            $result[0].Table | Should -BeExactly ""
            $result[0].Cmd | Should -BeExactly "DBCC CHECKIDENT('', NORESEED)"
            $result[1].IdentityValue | Should -BeExactly "125"
            ($warnings -join " ") | Should -BeLike "*Parameter 1 is incorrect*"
        }
    }

    Context "A table that cannot be read" {
        It "warns under the nested name and reports nulls, with either EnableException value" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            foreach ($enable in $false, $true) {
                $captured = @()
                $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.nosuchtable -EnableException:$enable -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured)
                $result.Count | Should -Be 1
                $result[0].Cmd | Should -BeExactly "DBCC CHECKIDENT('[dbo].[nosuchtable]', NORESEED)"
                $result[0].IdentityValue | Should -BeNullOrEmpty
                $result[0].ColumnValue | Should -BeNullOrEmpty
                $result[0].Output | Should -BeNullOrEmpty
                ($warnings -join " ") | Should -BeLike "*Invoke-DbaQuery*Failed during execution | Cannot find a table or object with the name*"

                # The caller's -ErrorVariable holds the nested Invoke-DbaQuery Stop-Function record, as the pinned nested call puts it
                # there (watchman 22dc72e0, central CaptureErrorVariable; pin edges case error-variable). The pin's also holds the
                # records of the nested query's own caught calls and blank entries (13 in all): accepted difference
                # omitted-consequential-records.
                $captured = @($captured)
                $captured.Count | Should -Be 1
                $captured[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $captured[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
                $captured[0].Exception.Message | Should -BeLike "Cannot find a table or object with the name*"
            }
        }

        It "warns of a table without an identity column" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.noident -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $result[0].IdentityValue | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*does not contain an identity column*"
        }

        It "goes on to the next table and reports only that table's values" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idmain, dbo.nosuchtable, dbo.idgap -WarningAction SilentlyContinue)
            $result.Count | Should -Be 3
            $result[0].IdentityValue | Should -BeExactly "125"
            $result[1].IdentityValue | Should -BeNullOrEmpty
            $result[2].IdentityValue | Should -BeExactly "2"
        }

        It "drops the warning under -ErrorAction SilentlyContinue or Ignore, as the nested query does" {
            foreach ($action in "SilentlyContinue", "Ignore") {
                $captured = @()
                $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.nosuchtable -ErrorAction $action -WarningVariable warnings -ErrorVariable captured)
                $result.Count | Should -Be 1
                $result[0].IdentityValue | Should -BeNullOrEmpty
                $warnings | Should -BeNullOrEmpty
                # Pin edges case error-variable-silently-continue: nothing reaches -ErrorVariable either.
                @($captured).Count | Should -Be 0
            }
        }

        It "keeps the warning and does not throw under -ErrorAction Stop" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.nosuchtable -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            ($warnings -join " ") | Should -BeLike "*Cannot find a table or object with the name*"
        }
    }

    Context "A database that cannot be opened" {
        It "warns and goes on to the next database" {
            $result = @(Get-DbaDbIdentity -SqlInstance $instance -Database $offlineDb, $mainDb -Table dbo.idmain -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $result[0].Database | Should -Be $mainDb
            ($warnings -join " ") | Should -BeLike "*The database ``[$offlineDb``] is not accessible. Skipping.*"
        }

        It "throws that warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            { Get-DbaDbIdentity -SqlInstance $instance -Database $offlineDb -Table dbo.idmain -EnableException } | Should -Throw -ExpectedMessage "The database ``[$offlineDb``] is not accessible. Skipping." -ErrorId "dbatools_Get-DbaDbIdentity*"
        }
    }

    Context "Without -Table" {
        It "warns for each piped instance and reads nothing" {
            $result = @($instance, $instance | Get-DbaDbIdentity -Database $mainDb -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            ($warnings -join " ") | Should -BeLike "*You must specify a table to execute against using -Table*"
        }

        It "throws that warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            { Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -EnableException } | Should -Throw -ExpectedMessage "You must specify a table to execute against using -Table" -ErrorId "dbatools_Get-DbaDbIdentity*"
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbIdentity -Database $mainDb -Table dbo.idmain).Count | Should -Be 2
        }

        It "reads through a server object and leaves its session in its database" {
            $before = $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME();")
            (Get-DbaDbIdentity -SqlInstance $server -Database $mainDb -Table dbo.idmain).IdentityValue | Should -BeExactly "125"
            $server.ConnectionContext.ExecuteScalar("SELECT DB_NAME();") | Should -Be $before
        }

        It "reads nothing under -WhatIf and everything under -Confirm:`$false" -Tag "NativeChecklist:whatif-confirm" {
            $output = @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idmain -WhatIf -Verbose 4>&1)
            @($output | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            (@($output | ForEach-Object { $PSItem.Message }) -join "|") | Should -Not -BeLike "*Query to run*"
            @(Get-DbaDbIdentity -SqlInstance $instance -Database $mainDb -Table dbo.idmain -Confirm:$false).Count | Should -Be 1
        }

        It "warns of a failed instance and goes on, and throws it under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $savedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
            $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            try {
                $listener.Start()
                $badInstance = "127.0.0.1," + $listener.LocalEndpoint.Port
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
                $result = @(Get-DbaDbIdentity -SqlInstance $badInstance, $server -Database $mainDb -Table dbo.idmain -EnableException:$false -WarningVariable failureWarnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 1
                ($failureWarnings -join " ") | Should -BeLike "*Failure*"
                { Get-DbaDbIdentity -SqlInstance $badInstance, $server -Database $mainDb -Table dbo.idmain -EnableException } | Should -Throw -ErrorId "dbatools_Get-DbaDbIdentity*"
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $savedTimeout
                $listener.Stop()
            }
        }
    }
}

Describe "Native Get-DbaDbIdentity on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $azureTable = "dbatoolsci_nid_$(Get-Random)"
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
        # Unique per leg and run: six legs share this database. AfterAll drops the table.
        $null = $azureServer.Query("CREATE TABLE dbo.$azureTable (Id int NOT NULL IDENTITY (125, 1), Value varchar(5)); INSERT INTO dbo.$azureTable (Value) SELECT '1';")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.Query("IF OBJECT_ID(N'dbo.$azureTable') IS NOT NULL DROP TABLE dbo.$azureTable;")
        }
    }

    It "reads a table through a connection to its database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = Get-DbaDbIdentity -SqlInstance $azureServer -Database $azureDatabase -Table "dbo.$azureTable"
        $result.Database | Should -BeExactly $azureDatabase
        $result.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result.IdentityValue | Should -BeExactly "125"
        $result.ColumnValue | Should -BeExactly "125"
    }

    It "reads a table from a connection of its own to the logical server" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = Get-DbaDbIdentity -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $azureDatabase -Table "dbo.$azureTable"
        $result.Database | Should -BeExactly $azureDatabase
        $result.IdentityValue | Should -BeExactly "125"
    }

    It "warns of a table that does not exist and reports nulls" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = Get-DbaDbIdentity -SqlInstance $azureServer -Database $azureDatabase -Table dbo.nosuchtable -WarningVariable warnings -WarningAction SilentlyContinue
        $result.IdentityValue | Should -BeNullOrEmpty
        ($warnings -join " ") | Should -BeLike "*Invoke-DbaQuery*Failed during execution | Cannot find a table or object with the name*"
    }
}

Describe "Native Get-DbaDbIdentity over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique per leg and run: the instance is shared.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $random = Get-Random
        $loginDb = "dbatoolsci_nidlogin_$random"
        $germanName = "dbatoolsci_nidde_$random"
        $germanPassword = "Nid-$([guid]::NewGuid().ToString('N'))"
        $germanCred = New-Object System.Management.Automation.PSCredential -ArgumentList $germanName, (ConvertTo-SecureString -String $germanPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred
        $null = $loginServer.Query("CREATE DATABASE [$loginDb];")
        $null = $loginServer.Query("CREATE LOGIN [$germanName] WITH PASSWORD = N'$germanPassword', CHECK_POLICY = OFF, DEFAULT_LANGUAGE = Deutsch;")
        $null = $loginServer.Query("CREATE TABLE dbo.idmain (Id int NOT NULL IDENTITY (125, 1), Value varchar(5)); INSERT INTO dbo.idmain (Value) SELECT '1'; CREATE USER [$germanName] FOR LOGIN [$germanName]; ALTER ROLE db_owner ADD MEMBER [$germanName];", $loginDb)
        $loginServer.Databases.Refresh()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$germanName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("USE [master]; IF DB_ID(N'$loginDb') IS NOT NULL BEGIN ALTER DATABASE [$loginDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$loginDb]; END;")
        $null = $loginServer.Query("IF SUSER_ID(N'$germanName') IS NOT NULL DROP LOGIN [$germanName];")
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = Get-DbaDbIdentity -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDb -Table dbo.idmain -EnableException
            $result.Database | Should -Be $loginDb
            $result.IdentityValue | Should -BeExactly "125"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbIdentity -SqlInstance $loginInstance -Database $loginDb -Table dbo.idmain -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*Login failed*"
        }

        # As the pin measured: the connection is the command's own, so the failure throws.
        It "throws the connection failure under -EnableException, as the pinned function does" {
            { Get-DbaDbIdentity -SqlInstance $loginInstance -Database $loginDb -Table dbo.idmain -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbIdentity*"
        }
    }

    Context "A login with another language" {
        It "reads the values from a message in the login's own language" {
            $result = Get-DbaDbIdentity -SqlInstance $loginInstance -SqlCredential $germanCred -Database $loginDb -Table dbo.idmain
            $result.Output[0] | Should -Not -BeLike "Checking identity information*"
            $result.IdentityValue | Should -BeExactly "125"
            $result.ColumnValue | Should -BeExactly "125"
        }
    }
}
