#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaDbMaskingConfig",
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
                "Column",
                "Path",
                "Locale",
                "CharacterString",
                "SampleCount",
                "KnownNameFilePath",
                "PatternFilePath",
                "ExcludeDefaultKnownName",
                "ExcludeDefaultPattern",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Known names" {
            BeforeAll {
                function New-MockMaskingDatabase {
                    param(
                        [string]$ColumnName
                    )

                    $mockServer = [PSCustomObject]@{
                        Name               = "sql1"
                        ComputerName       = "sql1"
                        ServiceName        = "MSSQLSERVER"
                        DomainInstanceName = "sql1"
                        VersionMajor       = 15
                    }
                    [PSCustomObject]@{
                        Name   = "db1"
                        Parent = $mockServer
                        Tables = @(
                            [PSCustomObject]@{
                                Name    = "Customer"
                                Schema  = "dbo"
                                Indexes = @()
                                Columns = @(
                                    [PSCustomObject]@{
                                        Name                = $ColumnName
                                        Identity            = $false
                                        IsForeignKey        = $false
                                        Computed            = $false
                                        GeneratedAlwaysType = "None"
                                        InPrimaryKey        = $false
                                        Nullable            = $true
                                        DataType            = [PSCustomObject]@{
                                            Name          = "nvarchar"
                                            SqlDataType   = "NVarChar"
                                            MaximumLength = 20
                                            NumericScale  = 0
                                        }
                                    }
                                )
                            }
                        )
                    }
                }

                function Get-MockMaskingColumn {
                    param(
                        [object]$File
                    )

                    (Get-Content -Path $File.FullName -Raw | ConvertFrom-Json).Tables.Columns
                }
            }

            It "uses the custom known names in -KnownNameFilePath next to the default ones" {
                $customKnownNameFile = Join-Path -Path $TestDrive -ChildPath "custom-knownnames.json"
                Set-Content -Path $customKnownNameFile -Value '[{ "Name": "Shoe size", "Category": "Personal", "Pattern": ["^ShoeSize$"], "MaskingType": "Lorem", "MaskingSubType": "Word" }]'
                $mockDatabase = New-MockMaskingDatabase -ColumnName "ShoeSize"
                Mock Get-DbaDatabase { $mockDatabase }

                # -ExcludeDefaultPattern, so that no rows are read
                $splatConfig = @{
                    SqlInstance           = "sql1"
                    Database              = "db1"
                    Path                  = $TestDrive
                    KnownNameFilePath     = $customKnownNameFile
                    ExcludeDefaultPattern = $true
                }
                $file = New-DbaDbMaskingConfig @splatConfig
                $column = Get-MockMaskingColumn -File $file

                $column.MaskingType | Should -Be "Lorem"
                $column.SubType | Should -Be "Word"
            }

            It "finds the column name <ColumnName> with a non-ASCII letter as <ExpectedSubType>" -ForEach @(
                # Built from code points, so that the test file itself stays ASCII for Windows PowerShell
                @{ ColumnName = "K$([char]0x00F6)n"; ExpectedSubType = "Gender" }
                @{ ColumnName = "F$([char]0x00F6)rnamn"; ExpectedSubType = "FirstName" }
            ) {
                $mockDatabase = New-MockMaskingDatabase -ColumnName $ColumnName
                Mock Get-DbaDatabase { $mockDatabase }

                $splatConfig = @{
                    SqlInstance           = "sql1"
                    Database              = "db1"
                    Path                  = $TestDrive
                    ExcludeDefaultPattern = $true
                }
                $file = New-DbaDbMaskingConfig @splatConfig
                $column = Get-MockMaskingColumn -File $file

                $column.Name | Should -Be $ColumnName
                $column.SubType | Should -Be $ExpectedSubType
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $maskingDbName = "dbatoolsci_maskconfig"
        $createPeopleTableSql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL
                ) ON [PRIMARY]"
        $testDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $maskingDbName
        $testDatabase.Query($createPeopleTableSql)
        $insertPeopleDataSql = "INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')"
        $testDatabase.Query($insertPeopleDataSql)

        # bug 6934
        $testDatabase.Query("
                CREATE TABLE dbo.DbConfigTest
                (
                    id              SMALLINT      NOT NULL,
                    IPAddress       VARCHAR(100)  NOT NULL,
                    Address         VARCHAR(100)  NOT NULL,
                    StreetAddress   VARCHAR(100)  NOT NULL,
                    Street          VARCHAR(100)  NOT NULL
                );
                INSERT INTO dbo.DbConfigTest (id, IPAddress, Address, StreetAddress, Street)
                VALUES
                (1, '127.0.0.1', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (2, '', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (3, 'fe80::7df3:7015:89e9:fbed%15', '123 Fake Street', '123 Fake Street', '123 Fake Street')")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $maskingDbName

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "Should output a file with specific content" {
            $splatMaskingConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $maskingDbName
                Path        = $backupPath
            }
            $configResults = New-DbaDbMaskingConfig @splatMaskingConfig

            $configResults.Directory.Name | Should -Match $CommandName
            $configResults.FullName | Should -FileContentMatch $maskingDbName
            $configResults.FullName | Should -FileContentMatch "fname"
        }

        It "Bug 6934: matching IPAddress, Address, and StreetAddress on known names" {
            $splatMaskingConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $maskingDbName
                Table       = "DbConfigTest"
                Path        = $backupPath
            }
            $configResults = New-DbaDbMaskingConfig @splatMaskingConfig
            $jsonOutput = Get-Content $configResults.FullName | ConvertFrom-Json

            $jsonOutput.Tables.Columns[1].Name | Should -Be "IPAddress"
            $jsonOutput.Tables.Columns[1].MaskingType | Should -Be "Internet"
            $jsonOutput.Tables.Columns[1].SubType | Should -Be "Ip"

            $jsonOutput.Tables.Columns[2].Name | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[3].Name | Should -Be "StreetAddress"
            $jsonOutput.Tables.Columns[3].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[3].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[4].Name | Should -Be "Street"
            $jsonOutput.Tables.Columns[4].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[4].SubType | Should -Be "StreetAddress"
        }
    }
}