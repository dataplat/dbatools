#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbPageInfo",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads page allocations.

Describe "Native Get-DbaDbPageInfo" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $suffix = Get-Random
        $firstName = "dbatoolsci_pgi_a_$suffix"
        $secondName = "dbatoolsci_pgi_b_$suffix"
        $offlineName = "dbatoolsci_pgo_$suffix"
        $badInstance = "TCP:127.0.0.1,1"
        # A Cyrillic word: none of its letters is in code page 1252, the code page of the collation the databases get here.
        $uni = -join [char[]](0x0441, 0x0445, 0x0435, 0x043C, 0x0430)
        $offlineMessage = "Database '$offlineName' cannot be opened because it is offline."
        $queryFailurePattern = "\[Get-DbaDbPageInfo\] Something went wrong executing the query \| " + [regex]::Escape($offlineMessage) + "$"
        $unsupportedPattern = "\[Get-DbaDbPageInfo\] Unsupported SQL Server version$"
        $unsupportedFailurePattern = "\[Get-DbaDbPageInfo\] Something went wrong executing the query \| Unsupported SQL Server version$"
        $connectFailurePattern = "\[Get-DbaDbPageInfo\] Failure"

        foreach ($name in @($firstName, $secondName, $offlineName)) {
            $null = $server.Query("CREATE DATABASE [$name] COLLATE SQL_Latin1_General_CP1_CI_AS;")
        }
        $server.Databases.Refresh()
        foreach ($statement in @(
                "CREATE SCHEMA sales;",
                "CREATE SCHEMA [$uni];",
                "CREATE SCHEMA [o'x];",
                "CREATE TABLE dbo.Customer (id int NOT NULL); INSERT dbo.Customer VALUES (1);",
                "CREATE TABLE sales.Customer (id int NOT NULL); INSERT sales.Customer VALUES (1);",
                "CREATE TABLE [$uni].Customer2 (id int NOT NULL); INSERT [$uni].Customer2 VALUES (1);",
                "CREATE TABLE [o'x].Quoted (id int NOT NULL); INSERT [o'x].Quoted VALUES (1);",
                "CREATE TABLE dbo.[we]]ird] (id int NOT NULL); INSERT dbo.[we]]ird] VALUES (1);",
                "CREATE TABLE dbo.[o'hara] (id int NOT NULL); INSERT dbo.[o'hara] VALUES (1);",
                "CREATE TABLE dbo.[a.b] (id int NOT NULL); INSERT dbo.[a.b] VALUES (1);"
            )) {
            $null = $server.Databases[$firstName].ExecuteNonQuery($statement)
        }
        foreach ($statement in @(
                "CREATE SCHEMA sales;",
                "CREATE TABLE dbo.Customer (id int NOT NULL); INSERT dbo.Customer VALUES (1);",
                "CREATE TABLE sales.Customer (id int NOT NULL); INSERT sales.Customer VALUES (1);"
            )) {
            $null = $server.Databases[$secondName].ExecuteNonQuery($statement)
        }
        $null = $server.Query("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()
        $first = $server.Databases[$firstName]
        $second = $server.Databases[$secondName]
        $offline = $server.Databases[$offlineName]

        # The tables a result holds, as database.schema.table, once each in the order they first come.
        function Get-TableKey {
            param($Rows)
            $tableKeys = foreach ($pageRow in $Rows) { "$($pageRow.Database).$($pageRow.Schema).$($pageRow.Table)" }
            @($tableKeys | Select-Object -Unique)
        }

        # The page rows the view itself returns for one table, read without the command.
        function Get-PageCount {
            param([string]$DatabaseName, [string]$SchemaName, [string]$TableName)
            $quoted = "[" + $SchemaName.Replace("]", "]]") + "].[" + $TableName.Replace("]", "]]") + "]"
            $countQuery = "SELECT COUNT(*) AS pages FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED') WHERE object_id = OBJECT_ID(N'" + $quoted.Replace("'", "''") + "');"
            [int]@($server.Databases[$DatabaseName].ExecuteWithResults($countQuery).Tables[0].Rows)[0].pages
        }
    }

    AfterAll {
        $null = $server.Query("IF DB_ID(N'$offlineName') IS NOT NULL ALTER DATABASE [$offlineName] SET ONLINE;")
        $null = Remove-DbaDatabase -SqlInstance $instance -Database $firstName, $secondName, $offlineName -Confirm:$false
    }

    Context "Output" {
        It "returns the raw rows of the page query with the pinned columns" {
            $rows = @(Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "dbo.Customer" -EnableException)
            $names = @($server.Query("SELECT CAST(SERVERPROPERTY('MachineName') AS nvarchar(128)) AS machine, CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS servername, CAST(ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS nvarchar(128)) AS instancename;"))[0]
            $rows.Count | Should -Be (Get-PageCount -DatabaseName $firstName -SchemaName "dbo" -TableName "Customer")
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row | Should -BeOfType [System.Data.DataRow]
                $row.Database | Should -BeExactly $firstName
                $row.Schema | Should -BeExactly "dbo"
                $row.Table | Should -BeExactly "Customer"
                $row.ComputerName | Should -BeExactly $names.machine
                $row.SqlInstance | Should -BeExactly $names.servername
                $row.InstanceName | Should -BeExactly $names.instancename
                $row.IsAllocated | Should -BeIn @("True", "False")
            }
            # A column named Table hides the row's own Table property, so the column list is read through the .NET view of the row.
            @($rows[0].psbase.Table.Columns | ForEach-Object ColumnName) -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,Table,PageType,PageFreePercent,IsAllocated,IsMixedPage"
            $allocated = @($rows | Where-Object IsAllocated -eq "True")
            $allocated.PageType | Should -Contain "IAM_PAGE"
            $allocated.PageType | Should -Contain "DATA_PAGE"
            foreach ($row in $allocated) {
                $row.IsMixedPage | Should -BeIn @("True", "False")
            }
        }

        It "puts the connection it was given back in the database it was in" {
            $caller = Connect-DbaInstance -SqlInstance $instance -Database $secondName -NonPooledConnection -EnableException
            try {
                $rows = @(Get-DbaDbPageInfo -SqlInstance $caller -Database $firstName -Table "dbo.Customer" -EnableException)
                $rows.Count | Should -BeGreaterThan 0
                $caller.ConnectionContext.CurrentDatabase | Should -BeExactly $secondName
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Databases" {
        It "reads only the databases of -Database, without regard to case or repetition, in the order of the instance" {
            $rows = Get-DbaDbPageInfo -SqlInstance $instance -Database $secondName.ToUpper(), $firstName, $firstName -Table "sales.Customer" -EnableException
            $keys = Get-TableKey $rows
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer|$secondName.sales.Customer"
            @($rows | Where-Object Database -eq $firstName).Count | Should -Be (Get-PageCount -DatabaseName $firstName -SchemaName "sales" -TableName "Customer")
        }

        It "reads every database for an empty -Database" {
            foreach ($form in @(@{ Database = "" }, @{ Database = $null }, @{ Database = @() })) {
                $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance @form -Table "sales.Customer" -WarningAction SilentlyContinue)
                $keys | Should -Contain "$firstName.sales.Customer"
                $keys | Should -Contain "$secondName.sales.Customer"
            }
        }

        It "reads the databases a wildcard -Database names" {
            $warnings = @()
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database "dbatoolsci_pgi_?_$suffix" -Table "sales.Customer" -WarningVariable warnings)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer|$secondName.sales.Customer"
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database "$firstName*" -Table "sales.Customer" -WarningVariable +warnings)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
            $warnings.Count | Should -Be 0
        }

        It "reads nothing and warns nothing for a database the instance does not have" {
            $warnings = @()
            @(Get-DbaDbPageInfo -SqlInstance $instance -Database "dbatoolsci_pgi_absent_$suffix" -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }
    }

    Context "Schemas" {
        It "reads only the tables of a -Schema name, without regard to case" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "SALES" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
        }

        It "reads the tables of each -Schema name" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "sales", "o'x" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly "$firstName.o'x.Quoted|$firstName.sales.Customer"
        }

        It "reads a -Schema name outside the database code page in any position" {
            $both = (@("$firstName.sales.Customer", "$firstName.$uni.Customer2") | Sort-Object) -join "|"
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "sales", $uni -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly $both
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema $uni, "sales" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly $both
        }

        It "reads every schema for an empty -Schema" {
            foreach ($form in @(@{ Schema = "" }, @{ Schema = $null }, @{ Schema = @() })) {
                $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName @form -EnableException)
                $keys | Should -Contain "$firstName.dbo.Customer"
                $keys | Should -Contain "$firstName.sales.Customer"
                $keys | Should -Contain "$firstName.$uni.Customer2"
            }
        }

        It "matches an empty -Schema element to no schema and reads the other names" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "", "sales" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
        }
    }

    Context "Tables" {
        It "reads a one part -Table name in every schema" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "Customer" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly "$firstName.dbo.Customer|$firstName.sales.Customer"
        }

        It "reads only the table a two part -Table name names, bracketed or not" {
            foreach ($name in @("sales.Customer", "[sales].[Customer]")) {
                $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table $name -EnableException)
                $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
            }
        }

        It "reads only the table a three part -Table name names in that database" {
            $rows = Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName, $secondName -Table "$firstName.sales.Customer" -EnableException
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
            @($rows).Count | Should -Be (Get-PageCount -DatabaseName $firstName -SchemaName "sales" -TableName "Customer")
        }

        It "reads nothing for a three part -Table name of another database" {
            $warnings = @()
            @(Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "$secondName.sales.Customer" -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }

        It "reads a three part -Table name with an empty schema in every schema of that database" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName, $secondName -Table "$firstName..Customer" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly "$firstName.dbo.Customer|$firstName.sales.Customer"
        }

        It "reads nothing for a -Table name of more than three parts" {
            @(Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "a.b.sales.Customer" -EnableException).Count | Should -Be 0
        }

        It "reads a -Table name with a doubled closing bracket" {
            foreach ($name in @("[we]]ird]", "dbo.[we]]ird]")) {
                $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table $name -EnableException)
                $keys -join "|" | Should -BeExactly "$firstName.dbo.we]ird"
            }
        }

        It "reads a -Table name or schema that holds a quote" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "o'hara" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.dbo.o'hara"
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "[o'x].Quoted" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.o'x.Quoted"
        }

        It "reads a bracketed -Table name that holds a dot" {
            foreach ($name in @("[a.b]", "dbo.[a.b]")) {
                $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table $name -EnableException)
                $keys -join "|" | Should -BeExactly "$firstName.dbo.a.b"
            }
        }

        It "reads a -Table schema outside the database code page" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "$uni.Customer2" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.$uni.Customer2"
        }

        It "reads each of several -Table names" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "sales.Customer", "[a.b]" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly "$firstName.dbo.a.b|$firstName.sales.Customer"
        }

        It "matches an empty -Table element to no table and reads the other names" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "", "sales.Customer" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
        }

        It "reads a -Table name only within the -Schema names" {
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "sales" -Table "Customer" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
            @(Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "dbo" -Table "sales.Customer" -EnableException).Count | Should -Be 0
            $keys = Get-TableKey (Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Schema "dbo", "sales" -Table "Customer" -EnableException)
            ($keys | Sort-Object) -join "|" | Should -BeExactly "$firstName.dbo.Customer|$firstName.sales.Customer"
        }
    }

    Context "Input" {
        It "reads piped databases, record by record or as one array" -Tag "NativeChecklist:pipeline-multiple" {
            $expected = "$secondName.sales.Customer|$firstName.sales.Customer"
            (Get-TableKey ($second, $first | Get-DbaDbPageInfo -Table "sales.Customer" -EnableException)) -join "|" | Should -BeExactly $expected
            (Get-TableKey (, @($second, $first) | Get-DbaDbPageInfo -Table "sales.Customer" -EnableException)) -join "|" | Should -BeExactly $expected
            (Get-TableKey (Get-DbaDbPageInfo -InputObject $second, $first -Table "sales.Customer" -EnableException)) -join "|" | Should -BeExactly $expected
        }

        It "reads a named instance once, after the first record's piped databases" {
            $pages = Get-PageCount -DatabaseName $firstName -SchemaName "sales" -TableName "Customer"
            $rows = @($second, $first | Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "sales.Customer" -EnableException)
            @($rows | Where-Object Database -eq $firstName).Count | Should -Be (2 * $pages)
            @($rows | Where-Object Database -eq $secondName).Count | Should -Be (Get-PageCount -DatabaseName $secondName -SchemaName "sales" -TableName "Customer")
            $rows[0].Database | Should -BeExactly $secondName
            $rows[-1].Database | Should -BeExactly $firstName
        }

        It "takes the pinned positions" {
            $keys = Get-TableKey (Get-DbaDbPageInfo $instance $null $firstName "sales" "Customer" -EnableException)
            $keys -join "|" | Should -BeExactly "$firstName.sales.Customer"
            $keys = Get-TableKey (Get-DbaDbPageInfo $null $null $null "sales" "Customer" $second -EnableException)
            $keys -join "|" | Should -BeExactly "$secondName.sales.Customer"
        }

        It "stops quietly when downstream takes only the first row" {
            $rows = @(Get-DbaDbPageInfo -SqlInstance $instance -Database $firstName -Table "sales.Customer" -EnableException | Select-Object -First 1)
            $rows.Count | Should -Be 1
            $rows[0].Table | Should -BeExactly "Customer"
        }
    }

    Context "Failures" {
        It "warns for a database that cannot be read and reads the next" {
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -InputObject $offline, $first -Table "sales.Customer" -WarningAction SilentlyContinue -WarningVariable warnings)
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $queryFailurePattern
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -SqlInstance $instance -Database $offlineName, $secondName -Table "sales.Customer" -WarningAction SilentlyContinue -WarningVariable warnings)
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$secondName.sales.Customer"
            $warnings.Count | Should -Be 1
        }

        It "throws the query failure for a database that cannot be read under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            $rows = @()
            try {
                Get-DbaDbPageInfo -InputObject $offline, $first -Table "sales.Customer" -EnableException -WarningAction SilentlyContinue | ForEach-Object { $rows += $PSItem }
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $rows.Count | Should -Be 0
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbPageInfo*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.Message | Should -BeExactly $offlineMessage
            $failure.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException
        }

        It "targets the instance last read when the query fails under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            $rows = @()
            try {
                Get-DbaDbPageInfo -SqlInstance $instance -Database $secondName, $offlineName -Table "sales.Customer" -EnableException -WarningAction SilentlyContinue | ForEach-Object { $rows += $PSItem }
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $offlineMessage
            "$($failure.TargetObject)" | Should -BeExactly "$instance"
            # The databases before it were already read.
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$secondName.sales.Customer"
        }

        It "only warns for a database that cannot be read under -ErrorAction Stop, as Stop-Function does" {
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -InputObject $offline, $first -Table "sales.Customer" -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings)
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
            $warnings.Count | Should -Be 1
        }

        It "warns for a null database or one without a server and reads the next" {
            $parentless = New-Object Microsoft.SqlServer.Management.Smo.Database
            foreach ($item in @($null, $parentless)) {
                $warnings = @()
                $rows = @(Get-DbaDbPageInfo -InputObject $item, $first -Table "sales.Customer" -WarningAction SilentlyContinue -WarningVariable warnings)
                (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match $unsupportedPattern
            }
        }

        It "reports a null database or one without a server as the query failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $parentless = New-Object Microsoft.SqlServer.Management.Smo.Database
            foreach ($item in @($null, $parentless)) {
                $warnings = @()
                $failure = $null
                $rows = @()
                try {
                    Get-DbaDbPageInfo -InputObject $item, $first -Table "sales.Customer" -EnableException -WarningAction SilentlyContinue -WarningVariable warnings | ForEach-Object { $rows += $PSItem }
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -Not -BeNullOrEmpty
                $rows.Count | Should -Be 0
                $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbPageInfo*"
                $failure.CategoryInfo.Category | Should -Be "NotSpecified"
                $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $failure.Exception.Message | Should -BeExactly "Unsupported SQL Server version"
                $failure.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Exception"
                $failure.Exception.InnerException.Message | Should -BeExactly "Unsupported SQL Server version"
                # The function's own catch takes the first Stop-Function's throw, so both messages are captured.
                $warnings.Count | Should -Be 2
                "$($warnings[0])" | Should -Match $unsupportedPattern
                "$($warnings[1])" | Should -Match $unsupportedFailurePattern
            }
        }

        It "warns for an instance it cannot reach and reads the next, also under -EnableException" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -SqlInstance $badInstance, $instance -Database $firstName -Table "sales.Customer" -WarningAction SilentlyContinue -WarningVariable warnings)
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
            ($warnings -join " ") | Should -Match $connectFailurePattern
            $failure = $null
            $rows = @()
            try {
                Get-DbaDbPageInfo -SqlInstance $badInstance, $instance -Database $firstName -Table "sales.Customer" -EnableException -WarningAction SilentlyContinue | ForEach-Object { $rows += $PSItem }
            } catch {
                $failure = $PSItem
            }
            $failure.CategoryInfo.Category | Should -Be "ConnectionError"
            $rows.Count | Should -Be 0
        }

        It "goes on for a false -EnableException switch" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -SqlInstance $badInstance, $instance -Database $firstName -Table "sales.Customer" -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            (Get-TableKey $rows) -join "|" | Should -BeExactly "$firstName.sales.Customer"
            ($warnings -join " ") | Should -Match $connectFailurePattern
        }
    }
}

Describe "Native Get-DbaDbPageInfo over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Unique per leg and run: the instance is shared.
            $loginDatabase = "dbatoolsci_pgi_login_$(Get-Random)"
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $null = $loginServer.Query("CREATE DATABASE [$loginDatabase];")
            $loginServer.Databases.Refresh()
            $null = $loginServer.Databases[$loginDatabase].ExecuteNonQuery("CREATE TABLE dbo.LoginPages (id int NOT NULL); INSERT dbo.LoginPages VALUES (1);")
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDatabase -Confirm:$false
        }

        It "works with -SqlCredential" {
            $rows = @(Get-DbaDbPageInfo -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDatabase -Table "dbo.LoginPages" -EnableException)
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row.Database | Should -BeExactly $loginDatabase
                $row.Table | Should -BeExactly "LoginPages"
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $rows = @(Get-DbaDbPageInfo -SqlInstance $loginInstance -Database $loginDatabase -Table "dbo.LoginPages" -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            # "Script-scope preferences and the one-line connect warning (operator, 2026-11-03)", point 5: one line naming the server.
            ($warnings -join " ") | Should -Match ("\[Get-DbaDbPageInfo\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed for user")
        }

        # The pinned function connects in its own try, whose Stop-Function throws under -EnableException.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $failure = $null
            $rows = @()
            $warnings = @()
            try {
                Get-DbaDbPageInfo -SqlInstance $loginInstance -Database $loginDatabase -Table "dbo.LoginPages" -EnableException -WarningAction SilentlyContinue -WarningVariable warnings | ForEach-Object { $rows += $PSItem }
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.CategoryInfo.Category | Should -Be "ConnectionError"
            $rows.Count | Should -Be 0
            # The same section, point 6: under -EnableException -WarningVariable holds that one line.
            @($warnings).Count | Should -Be 1
            "$(@($warnings)[0])" | Should -Match ("\[Get-DbaDbPageInfo\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed for user")
        }
    }

    # A low login connects in a home database and reads its databases there, then loses CONNECT to it: the query on a piped database
    # works and the USE back to the home database fails. Measured on the pin, evidence/pin-pageinfo-restore3-20261102.txt, and at the
    # port, evidence/probe-run-pageinfo-restore-engine-20261116-20261116181746.txt.
    Context "A connection that cannot go back to its database" {
        BeforeAll {
            $restoreInstance = $TestConfig.InstanceSqlLogin
            $restoreCred = $TestConfig.SqlLoginCred
            # Unique per leg and run: the instance is shared.
            $restoreStamp = Get-Random
            $homeName = "dbatoolsci_pgr_home_$restoreStamp"
            $readName = "dbatoolsci_pgr_read_$restoreStamp"
            $nextName = "dbatoolsci_pgr_next_$restoreStamp"
            $lowName = "dbatoolsci_pgr_low_$restoreStamp"
            $lowPassword = "Pgr-$([guid]::NewGuid().ToString('N'))"
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $restoreWarning = "The database context could not be restored to [$homeName]: Exception calling ""ExecuteNonQuery"" with ""1"" argument(s): ""An exception occurred while executing a Transact-SQL statement or batch."""
            $restoreServer = Connect-DbaInstance -SqlInstance $restoreInstance -SqlCredential $restoreCred -EnableException
            foreach ($name in @($homeName, $readName, $nextName)) {
                $null = $restoreServer.Query("CREATE DATABASE [$name];")
            }
            $null = $restoreServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
            $null = $restoreServer.Query("GRANT VIEW SERVER STATE TO [$lowName];")
            $restoreServer.Databases.Refresh()
            $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName];")
            foreach ($name in @($readName, $nextName)) {
                foreach ($statement in @(
                        "CREATE TABLE dbo.Pages (id int NOT NULL); INSERT dbo.Pages VALUES (1);",
                        "CREATE USER [$lowName] FOR LOGIN [$lowName];",
                        "ALTER ROLE db_owner ADD MEMBER [$lowName];"
                    )) {
                    $null = $restoreServer.Databases[$name].ExecuteNonQuery($statement)
                }
            }

            # A fresh connection of the low login in the home database, its two databases read while it may still connect there.
            function New-BrokenCaller {
                $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("GRANT CONNECT TO [$lowName];")
                $caller = Connect-DbaInstance -SqlInstance $restoreInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
                $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
                $piped = @($caller.Databases[$readName], $caller.Databases[$nextName])
                $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("DENY CONNECT TO [$lowName];")
                [pscustomobject]@{ Server = $caller; Piped = $piped }
            }

            # The databases a result holds, once each in the order they first come.
            function Get-RowDatabase {
                param($Rows)
                @($Rows | Where-Object { $PSItem -is [System.Data.DataRow] } | ForEach-Object { $PSItem.Database } | Select-Object -Unique)
            }

            # The pinned warning's text, measured on this leg: the pinned Database.Query script method writes
            # "The database context could not be restored to [$previousDatabase]: $($_.Exception.Message)", where $_ is its failed
            # $connectionContext.ExecuteNonQuery("USE [...]"). The same call on the same broken connection gives the same exception.
            function Get-PinnedRestoreText {
                param($Broken)
                $escapedHome = $homeName.Replace("]", "]]")
                $measured = $null
                try {
                    $null = $Broken.Server.ConnectionContext.ExecuteNonQuery("USE [$escapedHome]")
                } catch {
                    $measured = "The database context could not be restored to [$homeName]: $($PSItem.Exception.Message)"
                }
                $measured | Should -Not -BeNullOrEmpty -Because "the connection must still be unable to go back to its database"
                $measured
            }

            # Runs the command on the piped databases, then a next statement, in a runspace of its own created without a host, as in
            # the lab and as the probe measured it: the module this test loaded is imported there, and there is no interactive host,
            # so a prompt raises the engine's HostException at once instead of waiting. The warning goes into the output with 3>&1
            # under -Merge, else to the warning stream. Returns the rows, the warning records in the output and in Streams.Warning,
            # -WarningVariable, the error stream, whether the next statement ran, any throw and the seconds the call took.
            $noHostManifest = Join-Path (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase "dbatools.psd1"
            function Invoke-PageInfoNoHost {
                param($Piped, [hashtable]$Arguments, $Preference, [bool]$Merge)
                $noHostState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $noHostRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($noHostState)
                $noHostShell = [System.Management.Automation.PowerShell]::Create()
                $noHostOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $noHostThrow = $null
                try {
                    $noHostRunspace.Open()
                    $noHostImport = [System.Management.Automation.PowerShell]::Create()
                    try {
                        $noHostImport.Runspace = $noHostRunspace
                        $null = $noHostImport.AddCommand("Import-Module").AddParameter("Name", $noHostManifest).AddParameter("ErrorAction", "Stop").Invoke()
                    } finally {
                        $noHostImport.Dispose()
                    }
                    $noHostShell.Runspace = $noHostRunspace
                    $noHostScript = 'param($Piped, $Arguments, $Preference, $Merge)
$held = @()
if ($null -ne $Preference) { $WarningPreference = $Preference }
if ($Merge) {
    Get-DbaDbPageInfo -InputObject $Piped -Table "dbo.Pages" @Arguments -WarningVariable held 3>&1
} else {
    Get-DbaDbPageInfo -InputObject $Piped -Table "dbo.Pages" @Arguments -WarningVariable held
}
"next statement"'
                    $null = $noHostShell.AddScript($noHostScript).AddArgument($Piped).AddArgument($Arguments).AddArgument($Preference).AddArgument($Merge)
                    $noHostWatch = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        $null = $noHostShell.Invoke($null, $noHostOutput)
                    } catch {
                        $noHostThrow = $PSItem.Exception
                    }
                    $noHostWatch.Stop()
                    $noHostItems = @($noHostOutput | ForEach-Object { $PSItem.PSObject.BaseObject })
                    [PSCustomObject]@{
                        Rows           = @($noHostItems | Where-Object { $PSItem -is [System.Data.DataRow] })
                        PipeWarnings   = @($noHostItems | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] })
                        StreamWarnings = @($noHostShell.Streams.Warning)
                        Held           = @($noHostRunspace.SessionStateProxy.GetVariable("held"))
                        Errors         = @($noHostShell.Streams.Error)
                        Next           = @($noHostItems | Where-Object { "$PSItem" -ceq "next statement" }).Count -gt 0
                        Throw          = $noHostThrow
                        Seconds        = $noHostWatch.Elapsed.TotalSeconds
                    }
                } finally {
                    $noHostShell.Dispose()
                    $noHostRunspace.Dispose()
                }
            }

            # The rows of each database a result holds, as "<database> x <count>" in the order they first come.
            function Get-RowCount {
                param($Rows)
                $counts = [ordered]@{ }
                foreach ($row in @($Rows)) {
                    $key = [string]$row.Database
                    if ($counts.Contains($key)) { $counts[$key] = $counts[$key] + 1 } else { $counts[$key] = 1 }
                }
                @($counts.Keys | ForEach-Object { "$PSItem x $($counts[$PSItem])" })
            }

            # The engine's records of the one warning: exactly one WarningRecord, with the pinned text, where the form puts it.
            function Assert-RestoreWarning {
                param($Records, [string]$Text)
                @($Records).Count | Should -Be 1
                @($Records)[0] | Should -BeOfType [System.Management.Automation.WarningRecord]
                @($Records)[0].Message | Should -BeExactly $Text
            }
        }

        AfterAll {
            foreach ($row in @($restoreServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
                $null = $restoreServer.Query("KILL $($row.session_id);")
            }
            foreach ($name in @($homeName, $readName, $nextName)) {
                $null = $restoreServer.Query("IF DB_ID(N'$name') IS NOT NULL ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
                $null = $restoreServer.Query("IF DB_ID(N'$name') IS NOT NULL DROP DATABASE [$name];")
            }
            $null = $restoreServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        # "Database-context restore warning: ports follow the compiled cmdlet's warning preference (operator, 2026-11-15)", points
        # 1, 3 and 5: the port writes the pinned text with its own WriteWarning and the engine applies the preference. Each form
        # below asserts what probe pageinfo-restore-engine-20261116.ps1 measured at the port on 2017, 2019 and 2022 and on both
        # editions, in a runspace without a host (evidence/probe-run-pageinfo-restore-engine-20261116-20261116181746.txt, sha256
        # 239b9865...): every form writes the warning once, into the output under 3>&1 or else into the warning stream, unless
        # the preference drops it, and -WarningVariable always holds it. The pin's rows are 9 of each database
        # (evidence/pin-pageinfo-restore3-20261102.txt), and its connection stays in the database it read first.
        It "warns once with the pinned text and reads on under <label>, the warning <where>" -ForEach @(
            @{ label = "no preference"; arguments = @{ }; preference = $null; merge = $true; where = "merged into the output" },
            @{ label = "no preference"; arguments = @{ }; preference = $null; merge = $false; where = "in the warning stream" },
            @{ label = "a bound -WarningAction Continue"; arguments = @{ WarningAction = "Continue" }; preference = $null; merge = $true; where = "merged into the output" },
            @{ label = "a bound -WarningAction Continue"; arguments = @{ WarningAction = "Continue" }; preference = $null; merge = $false; where = "in the warning stream" },
            @{ label = "-EnableException"; arguments = @{ EnableException = $true }; preference = $null; merge = $true; where = "merged into the output" },
            @{ label = "-EnableException"; arguments = @{ EnableException = $true }; preference = $null; merge = $false; where = "in the warning stream" }
        ) {
            $broken = New-BrokenCaller
            try {
                $run = Invoke-PageInfoNoHost -Piped $broken.Piped -Arguments $arguments -Preference $preference -Merge $merge
                $run.Throw | Should -BeNullOrEmpty
                $run.Errors.Count | Should -Be 0
                $run.Next | Should -BeTrue
                (Get-RowCount $run.Rows) -join "|" | Should -BeExactly "$readName x 9|$nextName x 9"
                $broken.Server.ConnectionContext.CurrentDatabase | Should -BeExactly $readName
                $pinnedText = Get-PinnedRestoreText $broken
                $pinnedText | Should -BeExactly $restoreWarning
                if ($merge) {
                    Assert-RestoreWarning $run.PipeWarnings $pinnedText
                    $run.StreamWarnings.Count | Should -Be 0
                } else {
                    $run.PipeWarnings.Count | Should -Be 0
                    Assert-RestoreWarning $run.StreamWarnings $pinnedText
                }
                Assert-RestoreWarning $run.Held $pinnedText
            } finally {
                $broken.Server.ConnectionContext.Disconnect()
            }
        }

        # Point 3(c) and (d): SilentlyContinue and Ignore keep the warning out of the output and the warning stream; the engine
        # still puts it in -WarningVariable, and the call goes on.
        It "keeps the warning out of the output and the warning stream and reads on under <label><how>, -WarningVariable holding it" -ForEach @(
            @{ label = "SilentlyContinue"; how = " bound"; arguments = @{ WarningAction = "SilentlyContinue" }; preference = $null; merge = $true },
            @{ label = "SilentlyContinue"; how = " bound"; arguments = @{ WarningAction = "SilentlyContinue" }; preference = $null; merge = $false },
            @{ label = "SilentlyContinue"; how = " as the preference variable"; arguments = @{ }; preference = "SilentlyContinue"; merge = $true },
            @{ label = "SilentlyContinue"; how = " as the preference variable"; arguments = @{ }; preference = "SilentlyContinue"; merge = $false },
            @{ label = "Ignore"; how = " bound"; arguments = @{ WarningAction = "Ignore" }; preference = $null; merge = $true },
            @{ label = "Ignore"; how = " bound"; arguments = @{ WarningAction = "Ignore" }; preference = $null; merge = $false }
        ) {
            $broken = New-BrokenCaller
            try {
                $run = Invoke-PageInfoNoHost -Piped $broken.Piped -Arguments $arguments -Preference $preference -Merge $merge
                $run.Throw | Should -BeNullOrEmpty
                $run.Errors.Count | Should -Be 0
                $run.Next | Should -BeTrue
                (Get-RowCount $run.Rows) -join "|" | Should -BeExactly "$readName x 9|$nextName x 9"
                $broken.Server.ConnectionContext.CurrentDatabase | Should -BeExactly $readName
                $pinnedText = Get-PinnedRestoreText $broken
                $pinnedText | Should -BeExactly $restoreWarning
                $run.PipeWarnings.Count | Should -Be 0
                $run.StreamWarnings.Count | Should -Be 0
                Assert-RestoreWarning $run.Held $pinnedText
            } finally {
                $broken.Server.ConnectionContext.Disconnect()
            }
        }

        # Point 3(a): under Stop the warning is written and the engine then ends the call with ActionPreferenceStopException.
        # The restore fails on the first database, inside the query, before its rows, so no row is written; the caller's next
        # statement does not run.
        It "writes the warning and ends the call under Stop<how>, the warning <where>" -ForEach @(
            @{ how = " bound"; arguments = @{ WarningAction = "Stop" }; preference = $null; merge = $true; where = "merged into the output" },
            @{ how = " bound"; arguments = @{ WarningAction = "Stop" }; preference = $null; merge = $false; where = "in the warning stream" },
            @{ how = " as the preference variable"; arguments = @{ }; preference = "Stop"; merge = $true; where = "merged into the output" },
            @{ how = " as the preference variable"; arguments = @{ }; preference = "Stop"; merge = $false; where = "in the warning stream" }
        ) {
            $broken = New-BrokenCaller
            try {
                $run = Invoke-PageInfoNoHost -Piped $broken.Piped -Arguments $arguments -Preference $preference -Merge $merge
                $run.Next | Should -BeFalse
                $run.Rows.Count | Should -Be 0
                $broken.Server.ConnectionContext.CurrentDatabase | Should -BeExactly $readName
                $pinnedText = Get-PinnedRestoreText $broken
                $pinnedText | Should -BeExactly $restoreWarning
                $stops = @()
                for ($exception = $run.Throw; $null -ne $exception; $exception = $exception.InnerException) {
                    if ($exception -is [System.Management.Automation.ActionPreferenceStopException]) { $stops += $exception }
                }
                $stops.Count | Should -Be 1 -Because "the call must end with the engine's ActionPreferenceStopException: $($run.Throw)"
                $stops[0].Message | Should -BeExactly "The running command stopped because the preference variable ""WarningPreference"" or common parameter is set to Stop: $pinnedText"
                if ($merge) {
                    Assert-RestoreWarning $run.PipeWarnings $pinnedText
                    $run.StreamWarnings.Count | Should -Be 0
                } else {
                    $run.PipeWarnings.Count | Should -Be 0
                    Assert-RestoreWarning $run.StreamWarnings $pinnedText
                }
                Assert-RestoreWarning $run.Held $pinnedText
            } finally {
                $broken.Server.ConnectionContext.Disconnect()
            }
        }

        # Point 3(b): under Inquire, or -Debug with no bound -WarningAction, the engine asks after writing the warning. This
        # runspace cannot ask, so the command ends at once with the engine's HostException, a statement-terminating error: one
        # record in the error stream, no throw, and the caller's next statement runs. No row is written, as under Stop.
        It "writes the warning and ends the command with the engine's HostException, without waiting, under <label>, the warning <where>" -ForEach @(
            @{ label = "a bound -WarningAction Inquire"; arguments = @{ WarningAction = "Inquire" }; preference = $null; merge = $true; where = "merged into the output" },
            @{ label = "a bound -WarningAction Inquire"; arguments = @{ WarningAction = "Inquire" }; preference = $null; merge = $false; where = "in the warning stream" },
            @{ label = "Inquire as the preference variable"; arguments = @{ }; preference = "Inquire"; merge = $true; where = "merged into the output" },
            @{ label = "Inquire as the preference variable"; arguments = @{ }; preference = "Inquire"; merge = $false; where = "in the warning stream" },
            @{ label = "-Debug"; arguments = @{ Debug = $true }; preference = $null; merge = $true; where = "merged into the output" },
            @{ label = "-Debug"; arguments = @{ Debug = $true }; preference = $null; merge = $false; where = "in the warning stream" }
        ) {
            $broken = New-BrokenCaller
            try {
                $run = Invoke-PageInfoNoHost -Piped $broken.Piped -Arguments $arguments -Preference $preference -Merge $merge
                $run.Seconds | Should -BeLessThan 60
                $run.Throw | Should -BeNullOrEmpty
                $run.Next | Should -BeTrue
                $run.Rows.Count | Should -Be 0
                $run.Errors.Count | Should -Be 1
                $run.Errors[0].Exception | Should -BeOfType [System.Management.Automation.Host.HostException]
                $run.Errors[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotImplemented)
                $run.Errors[0].FullyQualifiedErrorId | Should -BeExactly "HostFunctionNotImplemented,Dataplat.Dbatools.Commands.GetDbaDbPageInfoCommand"
                $broken.Server.ConnectionContext.CurrentDatabase | Should -BeExactly $readName
                $pinnedText = Get-PinnedRestoreText $broken
                $pinnedText | Should -BeExactly $restoreWarning
                if ($merge) {
                    Assert-RestoreWarning $run.PipeWarnings $pinnedText
                    $run.StreamWarnings.Count | Should -Be 0
                } else {
                    $run.PipeWarnings.Count | Should -Be 0
                    Assert-RestoreWarning $run.StreamWarnings $pinnedText
                }
                Assert-RestoreWarning $run.Held $pinnedText
            } finally {
                $broken.Server.ConnectionContext.Disconnect()
            }
        }
    }
}

Describe "Native Get-DbaDbPageInfo on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        # Six legs share the database: a table of this run only.
        $azureTable = "pgi_" + [Guid]::NewGuid().ToString("N")
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureTable] (id int NOT NULL); INSERT dbo.[$azureTable] VALUES (1);")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureTable]') IS NOT NULL DROP TABLE dbo.[$azureTable];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "reads the pages of a table in the database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureRows = @(Get-DbaDbPageInfo -SqlInstance $azureServer -Database $TestConfig.AzureSqlDbName -Table "dbo.$azureTable" -EnableException)
        $azureRows.Count | Should -BeGreaterThan 0
        foreach ($row in $azureRows) {
            $row.Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $row.Schema | Should -BeExactly "dbo"
            $row.Table | Should -BeExactly $azureTable
        }
        @($azureRows | Where-Object IsAllocated -eq "True").Count | Should -BeGreaterThan 0
    }
}
