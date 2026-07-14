#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaDbCompression",
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
                "Database",
                "ExcludeDatabase",
                "Table",
                "View",
                "CompressionType",
                "MaxRunTime",
                "PercentCompression",
                "ForceOfflineRebuilds",
                "SortInTempDB",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Table name normalization" {
            BeforeAll {
                if (-not ("SetDbaDbCompressionTest.MockCollection[System.Object]" -as [type])) {
                    Add-Type -TypeDefinition @"
using System;
using System.Collections;
using System.Collections.Generic;

namespace SetDbaDbCompressionTest {
    public class MockCollection<T> : IEnumerable {
        private Dictionary<string, T> items = new Dictionary<string, T>(StringComparer.OrdinalIgnoreCase);

        public void Add(string name, T item) {
            items[name] = item;
        }

        public T this[string name] {
            get {
                T value;
                items.TryGetValue(name, out value);
                return value;
            }
        }

        public IEnumerator GetEnumerator() {
            return items.Values.GetEnumerator();
        }
    }

    public class MockDatabase {
        public string Name { get; set; }
        public bool IsAccessible { get; set; }
        public int IsSystemObject { get; set; }
        public string Status { get; set; }
        public string CompatibilityLevel { get; set; }
        public object[] Tables { get; set; }
        public object[] Views { get; set; }

        public override string ToString() {
            return Name;
        }
    }
}
"@
                }

                function Write-Message { }

                function New-MockCompressionTable {
                    param(
                        [string]$Schema,
                        [string]$Name
                    )

                    $table = [PSCustomObject]@{
                        Name                = $Name
                        Schema              = $Schema
                        IsMemoryOptimized   = $false
                        HasSparseColumn     = $false
                        Indexes             = @()
                        PhysicalPartitions  = @(
                            [PSCustomObject]@{
                                PartitionNumber = 1
                                DataCompression = "NONE"
                            }
                        )
                        OnlineHeapOperation = $false
                        HasHeapIndex        = $true
                    }
                    $table | Add-Member -Force -MemberType ScriptMethod -Name Rebuild -Value {
                        $script:rebuiltSchemas += $this.Schema
                    }

                    $table
                }

                function New-MockCompressionView {
                    param(
                        [string]$Schema,
                        [string]$Name
                    )

                    $view = [PSCustomObject]@{
                        Name    = $Name
                        Schema  = $Schema
                        Indexes = @()
                    }
                    $index = [PSCustomObject]@{
                        Name                     = "CX_$Name"
                        Parent                   = $view
                        IsMemoryOptimized        = $false
                        IndexType                = "ClusteredIndex"
                        IsOnlineRebuildSupported = $false
                        OnlineIndexOperation     = $false
                        SortInTempdb             = $false
                        Id                       = 1
                        PhysicalPartitions       = @(
                            [PSCustomObject]@{
                                PartitionNumber = 1
                                DataCompression = "NONE"
                            }
                        )
                    }
                    $index | Add-Member -Force -MemberType ScriptMethod -Name Rebuild -Value {
                        $script:rebuiltViews += $this.Parent.Schema
                    }
                    $view.Indexes = @($index)

                    $view
                }

                function New-MockCompressionFixture {
                    param(
                        [object[]]$Tables,
                        [object[]]$Views
                    )

                    $mockDatabase = New-Object "SetDbaDbCompressionTest.MockDatabase"
                    $mockDatabase.Name = "db1"
                    $mockDatabase.IsAccessible = $true
                    $mockDatabase.IsSystemObject = 0
                    $mockDatabase.Status = "Normal"
                    $mockDatabase.CompatibilityLevel = "Version160"
                    $mockDatabase.Tables = $Tables
                    $mockDatabase.Views = $Views

                    $mockDatabases = New-Object "SetDbaDbCompressionTest.MockCollection[System.Object]"
                    $mockDatabases.Add("db1", $mockDatabase)

                    [PSCustomObject]@{
                        ComputerName       = "sql1"
                        ServiceName        = "MSSQLSERVER"
                        DomainInstanceName = "sql1"
                        EngineEdition      = "Enterprise"
                        VersionMajor       = 16
                        isAzure            = $false
                        Databases          = $mockDatabases
                    }
                }
            }

            It "honors schema-qualified -Table input" {
                $script:rebuiltSchemas = @()
                $mockDatabase = New-Object "SetDbaDbCompressionTest.MockDatabase"
                $mockDatabase.Name = "db1"
                $mockDatabase.IsAccessible = $true
                $mockDatabase.IsSystemObject = 0
                $mockDatabase.Status = "Normal"
                $mockDatabase.CompatibilityLevel = "Version160"
                $mockDatabase.Tables = @(
                    (New-MockCompressionTable -Schema "dbo" -Name "Customer"),
                    (New-MockCompressionTable -Schema "sales" -Name "Customer")
                )

                $mockDatabases = New-Object "SetDbaDbCompressionTest.MockCollection[System.Object]"
                $mockDatabases.Add("db1", $mockDatabase)

                $mockServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    EngineEdition      = "Enterprise"
                    VersionMajor       = 16
                    isAzure            = $false
                    Databases          = $mockDatabases
                }

                Mock Connect-DbaInstance { $mockServer }
                Mock Stop-Function { throw $Message }

                $results = @(Set-DbaDbCompression -SqlInstance "sql1" -Database "db1" -Table "sales.Customer" -CompressionType Row)

                $results.Count | Should -Be 1
                $results[0].Schema | Should -Be "sales"
                $script:rebuiltSchemas | Should -Be @("sales")
            }

            It "does not process indexed views when Table is specified" {
                $script:rebuiltSchemas = @()
                $script:rebuiltViews = @()
                $mockServer = New-MockCompressionFixture -Tables @(
                    (New-MockCompressionTable -Schema "dbo" -Name "Customer"),
                    (New-MockCompressionTable -Schema "sales" -Name "Customer")
                ) -Views @(
                    (New-MockCompressionView -Schema "dbo" -Name "CustomerView")
                )

                Mock Connect-DbaInstance { $mockServer }
                Mock Stop-Function { throw $Message }

                $results = @(Set-DbaDbCompression -SqlInstance "sql1" -Database "db1" -Table "sales.Customer" -CompressionType Row)

                $results | Should -HaveCount 1
                $results[0].Schema | Should -Be "sales"
                $script:rebuiltViews | Should -BeNullOrEmpty
            }

            It "processes only the requested schema-qualified indexed view" {
                $script:rebuiltSchemas = @()
                $script:rebuiltViews = @()
                $mockServer = New-MockCompressionFixture -Tables @(
                    (New-MockCompressionTable -Schema "dbo" -Name "Customer")
                ) -Views @(
                    (New-MockCompressionView -Schema "dbo" -Name "CustomerView"),
                    (New-MockCompressionView -Schema "sales" -Name "CustomerView")
                )

                Mock Connect-DbaInstance { $mockServer }
                Mock Stop-Function { throw $Message }

                $results = @(Set-DbaDbCompression -SqlInstance "sql1" -Database "db1" -View "sales.CustomerView" -CompressionType Row)

                $results | Should -HaveCount 1
                $results[0].Schema | Should -Be "sales"
                $results[0].TableName | Should -Be "CustomerView"
                $script:rebuiltSchemas | Should -BeNullOrEmpty
                $script:rebuiltViews | Should -Be @("sales")
            }

            It "continues to process tables and indexed views when neither filter is specified" {
                $script:rebuiltSchemas = @()
                $script:rebuiltViews = @()
                $mockServer = New-MockCompressionFixture -Tables @(
                    (New-MockCompressionTable -Schema "dbo" -Name "Customer")
                ) -Views @(
                    (New-MockCompressionView -Schema "dbo" -Name "CustomerView")
                )

                Mock Connect-DbaInstance { $mockServer }
                Mock Stop-Function { throw $Message }

                $results = @(Set-DbaDbCompression -SqlInstance "sql1" -Database "db1" -CompressionType Row)

                $results | Should -HaveCount 2
                $script:rebuiltSchemas | Should -Be @("dbo")
                $script:rebuiltViews | Should -Be @("dbo")
            }

            It "rejects View with Recommended compression" {
                Mock Stop-Function { throw $Message }

                { Set-DbaDbCompression -SqlInstance "sql1" -View "dbo.CustomerView" } | Should -Throw "*explicit CompressionType*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "dbatoolsci_test_$(Get-Random)"
        $indexedViewName = "dbatoolsci_syscolview"
        $indexedViewIndexName = "CL_dbatoolsci_syscolview"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("Create Database [$dbName]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET QUOTED_IDENTIFIER ON;
                               EXEC sys.sp_executesql N'CREATE VIEW dbo.[$indexedViewName]
                               WITH SCHEMABINDING
                               AS
                               SELECT object_id, column_id
                               FROM dbo.syscols'", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET ANSI_PADDING ON;
                               SET ANSI_WARNINGS ON;
                               SET ARITHABORT ON;
                               SET CONCAT_NULL_YIELDS_NULL ON;
                               SET QUOTED_IDENTIFIER ON;
                               SET NUMERIC_ROUNDABORT OFF;
                               CREATE UNIQUE CLUSTERED INDEX [$indexedViewIndexName] ON dbo.[$indexedViewName] (object_id, column_id)", $dbName)

        # Get InputObject for testing
        $inputObject = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command gets results" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
        }

        It "Should contain objects" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
            $heapsAndClustered = $results | Where-Object IndexId -le 1
        }

        It "Should process heap and clustered index objects" {
            foreach ($row in $heapsAndClustered) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command handles nonclustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
            $nonClusteredIndexes = $results | Where-Object IndexId -gt 1
        }

        It "Should process nonclustered index objects" {
            foreach ($row in $nonClusteredIndexes) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command excludes results for specified database" {
        BeforeAll {
            $server.Databases[$dbName].Tables["syscols"].PhysicalPartitions[0].DataCompression = "NONE"
            $server.Databases[$dbName].Tables["syscols"].Rebuild()
            $excludeResults = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -ExcludeDatabase $dbName -MaxRunTime 5 -PercentCompression 0
        }

        It "Shouldn't get any results for excluded database" {
            $excludeResults.Database | Should -Not -Match $dbName
        }
    }

    Context "Command can accept InputObject from Test-DbaDbCompression" {
        BeforeAll {
            $inputObjectResults = @(Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0 -InputObject $inputObject)
        }

        It "Should get results from InputObject" {
            $inputObjectResults | Should -Not -BeNullOrEmpty
        }

        It "Should process all objects from InputObject" {
            foreach ($row in $inputObjectResults) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command sets compression to Row all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Row
            $rowResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to Row compression" {
            foreach ($row in $rowResults) {
                $row.DataCompression | Should -Be "Row"
            }
        }
    }

    Context "Command sets compression to Page for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Page
            $pageResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to Page compression" {
            foreach ($row in $pageResults) {
                $row.DataCompression | Should -Be "Page"
            }
        }
    }

    Context "Command sets compression to None for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType None
            $noneResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to no compression" {
            foreach ($row in $noneResults) {
                $row.DataCompression | Should -Be "None"
            }
        }
    }

    Context "Command returns indexed view metadata when rebuilding to None" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Page
            $indexedViewResults = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType None |
                Where-Object IndexName -eq $indexedViewIndexName
        }

        It "Should return the indexed view schema and name" {
            $indexedViewResults | Should -Not -BeNullOrEmpty
            foreach ($row in $indexedViewResults) {
                $row.Schema | Should -Be "dbo"
                $row.TableName | Should -Be $indexedViewName
            }
        }
    }
}
