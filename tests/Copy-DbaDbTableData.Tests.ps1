#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaDbTableData",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "DestinationDatabase",
                "Table",
                "View",
                "Query",
                "ForceExplicitMapping",
                "AutoCreateTable",
                "BatchSize",
                "NotifyAfter",
                "DestinationTable",
                "NoTableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Truncate",
                "BulkCopyTimeout",
                "CommandTimeout",
                "UseDefaultFileGroup",
                "ScriptingOptionsObject",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Auto-creating a standard table from an external source" {
            BeforeEach {
                $script:capturedCreateQuery = $null
                $script:stopErrorMessage = $null
                $sourceServer = [PSCustomObject]@{
                    Name = "source"
                }
                $sourceDatabase = [PSCustomObject]@{
                    Name   = "sourcedb"
                    ID     = 1
                    Parent = $sourceServer
                }
                $script:externalTable = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.SqlServer.Management.Smo.Table])
                $script:externalTable | Add-Member -MemberType NoteProperty -Name Schema -Value "dbo" -Force
                $script:externalTable | Add-Member -MemberType NoteProperty -Name Name -Value "ExternalOrders" -Force
                $script:externalTable | Add-Member -MemberType NoteProperty -Name IsExternal -Value $true -Force
                $script:externalTable | Add-Member -MemberType NoteProperty -Name Parent -Value $sourceDatabase -Force
                $script:externalTable | Add-Member -MemberType NoteProperty -Name Columns -Force -Value @(
                    [PSCustomObject]@{
                        Name      = "OrderId"
                        DataType  = [Microsoft.SqlServer.Management.Smo.DataType]::Int
                        Nullable  = $false
                        Collation = $null
                    },
                    [PSCustomObject]@{
                        Name      = "Description"
                        DataType  = [Microsoft.SqlServer.Management.Smo.DataType]::NVarChar(200)
                        Nullable  = $true
                        Collation = "Latin1_General_100_CI_AS_SC_UTF8"
                    },
                    [PSCustomObject]@{
                        Name      = "Amount"
                        DataType  = [Microsoft.SqlServer.Management.Smo.DataType]::Decimal(4, 18)
                        Nullable  = $false
                        Collation = $null
                    }
                )
                $script:destinationServer = [DbaInstanceParameter]"destination"
                $script:destinationServer | Add-Member -MemberType NoteProperty -Name Name -Value "destination" -Force
                $script:destinationServer | Add-Member -MemberType NoteProperty -Name Databases -Force -Value @(
                    [PSCustomObject]@{
                        Name = "destinationdb"
                    }
                )

                Mock Connect-DbaInstance {
                    $script:destinationServer
                }
                Mock Get-DbaDbTable -RemoveParameterType "SqlInstance" {
                    return $null
                }
                Mock New-DbaScriptingOption {
                    [PSCustomObject]@{
                        NoFileGroup = $false
                    }
                }
                Mock Export-DbaScript {
                    throw "External tables must not use SMO scripting."
                }
                Mock Invoke-DbaQuery -RemoveParameterType "SqlInstance" {
                    $script:capturedCreateQuery = $Query
                    throw "Stop after capturing destination DDL."
                }
                Mock Stop-Function {
                    param($Message, $ErrorRecord)
                    if ($ErrorRecord) {
                        $script:stopErrorMessage = $ErrorRecord.Exception.Message
                        throw "$Message Inner error: $($ErrorRecord.Exception.Message)"
                    }
                    throw $Message
                }
            }

            It "renders external columns as an ordinary destination table" {
                $splatCopy = @{
                    InputObject         = $script:externalTable
                    Destination         = "destination"
                    DestinationDatabase = "destinationdb"
                    DestinationTable    = "[archive].[OrdersCopy]"
                    AutoCreateTable     = $true
                    Confirm             = $false
                }

                $copyExternalTableAction = { Copy-DbaDbTableData @splatCopy }
                $copyExternalTableAction | Should -Throw "*Unable to determine destination table*"

                $script:stopErrorMessage | Should -Be "Stop after capturing destination DDL."
                $script:capturedCreateQuery | Should -Match "CREATE TABLE \[archive\]\.\[OrdersCopy\]"
                $script:capturedCreateQuery | Should -Match "\[OrderId\] int NOT NULL"
                $script:capturedCreateQuery | Should -Match "\[Description\] nvarchar\(200\) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL"
                $script:capturedCreateQuery | Should -Match "\[Amount\] decimal\(18,4\) NOT NULL"
                Should -Invoke Export-DbaScript -Times 0 -Exactly
            }

            It "uses standard scripting when IsExternal is unsupported" {
                $script:externalTable | Add-Member -MemberType ScriptProperty -Name IsExternal -Value { throw "IsExternal is unsupported." } -Force
                Mock Export-DbaScript {
                    "CREATE TABLE [dbo].[ExternalOrders] ([OrderId] int NOT NULL);"
                }

                $splatCopy = @{
                    InputObject         = $script:externalTable
                    Destination         = "destination"
                    DestinationDatabase = "destinationdb"
                    DestinationTable    = "[archive].[OrdersCopy]"
                    AutoCreateTable     = $true
                    Confirm             = $false
                }

                $copyUnsupportedExternalPropertyAction = { Copy-DbaDbTableData @splatCopy }
                $copyUnsupportedExternalPropertyAction | Should -Throw "*Unable to determine destination table*"

                $script:stopErrorMessage | Should -Be "Stop after capturing destination DDL."
                $script:capturedCreateQuery | Should -Match "CREATE TABLE \[archive\]\.\[OrdersCopy\]"
                Should -Invoke Export-DbaScript -Times 1 -Exactly
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb
        $destinationDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 2
            FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example2")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE tempdb.dbo.dbatoolsci_willexist")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying table data within same instance" {
        It "copies the table data" {
            $results = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $sourceDb.ID
        }
    }

    Context "When copying table data between instances" {
        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $destinationDb.Query("select id from dbo.dbatoolsci_example3")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "Copy data using a query that relies on the default source database" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Copy data using a query that uses a 3 part query" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }
    }

    Context "When testing pipeline functionality" {
        It "supports piping" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -ExpandProperty Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example4" | Copy-DbaDbTableData -Destination $TestConfig.InstanceCopy2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
            $results.Count | Should -Be 2
            $table1DbCount = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4DbCount = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1Db2Count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4Db2Count = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1DbCount.Count | Should -Be $table1Db2Count.Count
            $table4DbCount.Count | Should -Be $table4Db2Count.Count
            $results[0].RowsCopied | Should -Be 10
            $results[1].RowsCopied | Should -Be 13
            $table4Db2Check = $destinationDb.Query("select id from dbo.dbatoolsci_example4 where id = 1")
            $table4Db2Check.Count | Should -Be 13
        }
    }

    Context "When handling edge cases" {
        It "Should return nothing if Source and Destination are same" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -Truncate -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -Be $null
            $warn | Should -Match "Cannot copy .* into itself"
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be "dbatoolsci_willexist"
        }
    }

    Context "When destination table has computed columns" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_computed_source (Dt DATETIME)")
            $null = $sourceDb.Query("INSERT dbo.dbatoolsci_computed_source (Dt) VALUES (GETDATE()), (DATEADD(MONTH, -1, GETDATE()))")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_computed_dest (Dt DATETIME, DtDay AS (DATEPART(DAY, Dt)), DtMonth AS (DATEPART(MONTH, Dt)), DtYear AS (DATEPART(YEAR, Dt)))")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy data successfully when destination has computed columns" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table dbatoolsci_computed_source -DestinationTable dbatoolsci_computed_dest
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }

        It "Should copy data using Query with ForceExplicitMapping when destination has computed columns" {
            # First truncate dest table
            $null = $destinationDb.Query("TRUNCATE TABLE dbo.dbatoolsci_computed_dest")

            # Use Query parameter with ForceExplicitMapping to enable name-based column mapping
            # This is needed when using Query with tables that have computed columns
            $splatCopy = @{
                SqlInstance          = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Database             = "tempdb"
                Table                = "dbatoolsci_computed_source"
                Query                = "SELECT Dt FROM dbo.dbatoolsci_computed_source"
                DestinationTable     = "dbatoolsci_computed_dest"
                ForceExplicitMapping = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }
    }

    Context "Regression tests" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_ordering_test (id INT IDENTITY(1,1) PRIMARY KEY, data_hash VARBINARY(32))")
            $null = $sourceDb.Query("INSERT INTO dbo.dbatoolsci_ordering_test (data_hash) VALUES (0x0102030405), (0x0607080910), (0x1112131415)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should maintain correct row order when copying tables with varbinary fields (issue #9610)" {
            $splatCopy = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_ordering_test"
                DestinationTable = "dbatoolsci_ordering_test_dest"
                AutoCreateTable  = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 3

            $sourceData = $sourceDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test ORDER BY id")
            $destData = $destinationDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test_dest ORDER BY id")

            for ($i = 0; $i -lt $sourceData.Count; $i++) {
                $sourceData[$i].id | Should -Be $destData[$i].id
                $sourceData[$i].data_hash | Should -Be $destData[$i].data_hash
            }
        }
    }
}
