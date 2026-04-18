#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaBalanceDataFiles",
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
                "Table",
                "TargetFileGroup",
                "RebuildOffline",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Table name normalization" {
            BeforeAll {
                if (-not ("InvokeDbaBalanceDataFilesTest.MockCollection[System.Object]" -as [type])) {
                    Add-Type -TypeDefinition @"
using System;
using System.Collections;
using System.Collections.Generic;

namespace InvokeDbaBalanceDataFilesTest {
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
}
"@
                }

                function Write-Message { }

                function New-MockBalanceIndex {
                    param(
                        [string]$Schema,
                        [string]$Name
                    )

                    $index = [PSCustomObject]@{
                        Name                 = "PK_${Schema}_$Name"
                        TableSchema          = $Schema
                        IndexType            = "ClusteredIndex"
                        OnlineIndexOperation = $false
                        FileGroup            = "PRIMARY"
                    }
                    $index | Add-Member -Force -MemberType ScriptMethod -Name Rebuild -Value {
                        $script:rebuiltSchemas += $this.TableSchema
                    }

                    $index
                }

                function New-MockBalanceTable {
                    param(
                        [object]$Database,
                        [string]$Schema,
                        [string]$Name
                    )

                    [PSCustomObject]@{
                        Name    = $Name
                        Schema  = $Schema
                        Parent  = $Database
                        Indexes = @(New-MockBalanceIndex -Schema $Schema -Name $Name)
                    }
                }
            }

            It "honors schema-qualified -Table input" {
                $script:rebuiltSchemas = @()
                $fileGroups = New-Object "InvokeDbaBalanceDataFilesTest.MockCollection[System.Object]"
                $fileGroups.Add("PRIMARY", [PSCustomObject]@{
                        Name     = "PRIMARY"
                        Readonly = $false
                        Files    = @(
                            [PSCustomObject]@{
                                Name = "primaryfile"
                            }
                        )
                    })

                $mockDatabase = [PSCustomObject]@{
                    Name       = "db1"
                    FileGroups = $fileGroups
                }
                $mockDatabase | Add-Member -Force -MemberType ScriptMethod -Name ToString -Value {
                    $this.Name
                }
                $mockDatabase | Add-Member -Force -MemberType NoteProperty -Name Tables -Value @(
                    (New-MockBalanceTable -Database $mockDatabase -Schema "dbo" -Name "Customer"),
                    (New-MockBalanceTable -Database $mockDatabase -Schema "sales" -Name "Customer")
                )

                $mockDatabases = New-Object "InvokeDbaBalanceDataFilesTest.MockCollection[System.Object]"
                $mockDatabases.Add("db1", $mockDatabase)

                $mockServer = [DbaInstanceParameter]"sql1"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "sql1"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "sql1"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Databases -Value $mockDatabases
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Version -Value ([PSCustomObject]@{
                        Major = 16
                    })
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Edition -Value "Enterprise"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name HostPlatform -Value "Linux"
                $mockDataFiles = @(
                    [PSCustomObject]@{
                        ID              = 1
                        LogicalName     = "db1"
                        PhysicalName    = "C:\db1.mdf"
                        Size            = 10
                        UsedSpace       = 5
                        AvailableSpace  = 5
                        TypeDescription = "ROWS"
                    },
                    [PSCustomObject]@{
                        ID              = 2
                        LogicalName     = "db1_2"
                        PhysicalName    = "C:\db1_2.ndf"
                        Size            = 10
                        UsedSpace       = 5
                        AvailableSpace  = 5
                        TypeDescription = "ROWS"
                    }
                )

                Mock Connect-DbaInstance { $mockServer }
                Mock Get-DbaDbFile { $mockDataFiles }
                Mock Stop-Function { throw $Message }

                $results = @(Invoke-DbaBalanceDataFiles -SqlInstance "sql1" -Database "db1" -Table "sales.Customer" -TargetFileGroup "PRIMARY" -RebuildOffline -Force)

                $results.Count | Should -Be 1
                $results[0].Success | Should -BeTrue
                $script:rebuiltSchemas | Should -Be @("sales")
            }
        }

        Context "Target filegroup validation" {
            It "fails when the target filegroup does not contain any data files" {
                $fileGroups = New-Object "InvokeDbaBalanceDataFilesTest.MockCollection[System.Object]"
                $fileGroups.Add("EMPTYFG", [PSCustomObject]@{
                        Name     = "EMPTYFG"
                        Readonly = $false
                        Files    = @()
                    })

                $mockDatabase = [PSCustomObject]@{
                    Name       = "db1"
                    FileGroups = $fileGroups
                    Tables     = @()
                }
                $mockDatabase | Add-Member -Force -MemberType ScriptMethod -Name ToString -Value {
                    $this.Name
                }

                $mockDatabases = New-Object "InvokeDbaBalanceDataFilesTest.MockCollection[System.Object]"
                $mockDatabases.Add("db1", $mockDatabase)

                $mockServer = [DbaInstanceParameter]"sql1"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Databases -Value $mockDatabases
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Version -Value ([PSCustomObject]@{
                        Major = 16
                    })
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name Edition -Value "Enterprise"
                $mockServer | Add-Member -Force -MemberType NoteProperty -Name HostPlatform -Value "Linux"
                $mockDataFiles = @(
                    [PSCustomObject]@{
                        ID              = 1
                        LogicalName     = "db1"
                        PhysicalName    = "C:\db1.mdf"
                        Size            = 10
                        UsedSpace       = 5
                        AvailableSpace  = 5
                        TypeDescription = "ROWS"
                    },
                    [PSCustomObject]@{
                        ID              = 2
                        LogicalName     = "db1_2"
                        PhysicalName    = "C:\db1_2.ndf"
                        Size            = 10
                        UsedSpace       = 5
                        AvailableSpace  = 5
                        TypeDescription = "ROWS"
                    }
                )

                Mock Connect-DbaInstance { $mockServer }
                Mock Get-DbaDbFile { $mockDataFiles }
                Mock Stop-Function { throw $Message }

                {
                    Invoke-DbaBalanceDataFiles -SqlInstance "sql1" -Database "db1" -TargetFileGroup "EMPTYFG" -RebuildOffline -Force
                } | Should -Throw "*does not contain any data files*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create the server object
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Get the default data directory to create the additional data file
        $defaultdata = (Get-DbaDefaultPath -SqlInstance $server).Data

        # Set the database name
        $dbname = "dbatoolscsi_balance"

        # Create the database
        $server.Query("CREATE DATABASE [$dbname]")

        # Refresh the database to get all the latest changes
        $server.Databases.Refresh()

        # retrieve the database object for later
        $db = Get-DbaDatabase -SqlInstance $server -Database $dbname

        # Create the tables
        $db.Query("CREATE TABLE table1 (ID1 INT IDENTITY PRIMARY KEY, Name1 char(100))")
        $db.Query("CREATE TABLE table2 (ID1 INT IDENTITY PRIMARY KEY, Name2 char(100))")

        # Generate the values
        $sqlvalues = New-Object System.Collections.ArrayList
        1 .. 1000 | ForEach-Object { $null = $sqlvalues.Add("('some value')") }

        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table1 (Name1) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")
        $db.Query("insert into table2 (Name2) Values $($sqlvalues -join ',')")

        $db.Query("ALTER DATABASE [$dbname] ADD FILEGROUP [EMPTYFG]")
        $db.Query("ALTER DATABASE $dbname ADD FILE (NAME = secondfile, FILENAME = '$defaultdata\$dbname-secondaryfg.ndf') TO FILEGROUP [PRIMARY]")

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $server -Database $dbname
    }

    Context "Data is balanced among data files" {
        BeforeAll {
            $results = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -RebuildOffline -Force
        }

        It "Result returns success" {
            $results.Success | Should -BeTrue
        }

        It "New used space should be less" {
            $sizeUsedBefore = $results.DataFilesStart[0].UsedSpace.Kilobyte
            $sizeUsedAfter = $results.DataFilesEnd[0].UsedSpace.Kilobyte

            $sizeUsedAfter | Should -BeLessThan $sizeUsedBefore
        }
    }

    Context "Target filegroup validation" {
        It "warns when the target filegroup does not contain any data files" {
            $warningMessages = $null
            $results = Invoke-DbaBalanceDataFiles -SqlInstance $server -Database $dbname -TargetFileGroup "EMPTYFG" -RebuildOffline -Force -WarningAction SilentlyContinue -WarningVariable warningMessages

            $results | Should -BeNullOrEmpty
            ($warningMessages | Out-String) | Should -Match "does not contain any data files"
        }
    }
}
