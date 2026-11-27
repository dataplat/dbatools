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
                        [string]$ColumnName,
                        [string]$DataTypeName = "nvarchar",
                        [int]$MaximumLength = 20
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
                                            Name          = $DataTypeName
                                            SqlDataType   = $DataTypeName
                                            MaximumLength = $MaximumLength
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

            It "masks the <DataTypeName> column <ColumnName> as <ExpectedType>/<ExpectedSubType>" -ForEach @(
                # Person/Gender, Phone/PhoneNumber and Person/DateOfBirth do not produce numbers, so the data type decides
                @{ ColumnName = "Kon"; DataTypeName = "tinyint"; MaximumLength = 1; ExpectedType = "Random"; ExpectedSubType = "Number" }
                @{ ColumnName = "K$([char]0x00F6)n"; DataTypeName = "tinyint"; MaximumLength = 1; ExpectedType = "Random"; ExpectedSubType = "Number" }
                @{ ColumnName = "Gender"; DataTypeName = "bit"; MaximumLength = 1; ExpectedType = "Random"; ExpectedSubType = "Bool" }
                @{ ColumnName = "Telefon"; DataTypeName = "bigint"; MaximumLength = 8; ExpectedType = "Random"; ExpectedSubType = "Number" }
                @{ ColumnName = "Fodelsedatum"; DataTypeName = "int"; MaximumLength = 4; ExpectedType = "Random"; ExpectedSubType = "Number" }
                # Random/Int produces numbers, so the National ID recommendation stays
                @{ ColumnName = "Personnummer"; DataTypeName = "bigint"; MaximumLength = 8; ExpectedType = "Random"; ExpectedSubType = "Int" }
            ) {
                $mockDatabase = New-MockMaskingDatabase -ColumnName $ColumnName -DataTypeName $DataTypeName -MaximumLength $MaximumLength
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
                $column.ColumnType | Should -Be $DataTypeName
                $column.MaskingType | Should -Be $ExpectedType
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

        # A gender code in a numeric column with a Nordic name, which matches the Gender known name
        $testDatabase.Query("
                CREATE TABLE dbo.Person
                (
                    Id  INT IDENTITY PRIMARY KEY,
                    Kon TINYINT NOT NULL
                );
                INSERT INTO dbo.Person (Kon)
                SELECT 1 + (n % 2) FROM (SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) AS numbers;")

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

        It "Generates a configuration that masks a gender code in a tinyint column" {
            $splatQuery = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $maskingDbName
                Query       = "SELECT Id, Kon FROM dbo.Person ORDER BY Id"
            }
            $before = @(Invoke-DbaQuery @splatQuery)

            $splatMaskingConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $maskingDbName
                Table       = "Person"
                Path        = $backupPath
            }
            $configResults = New-DbaDbMaskingConfig @splatMaskingConfig
            $jsonOutput = Get-Content $configResults.FullName | ConvertFrom-Json
            $konColumn = $jsonOutput.Tables.Columns | Where-Object Name -eq "Kon"

            # Person/Gender would generate Male or Female, which cannot be written to a tinyint
            $konColumn.MaskingType | Should -Be "Random"
            $konColumn.SubType | Should -Be "Number"

            $splatMasking = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $maskingDbName
                FilePath    = $configResults.FullName
            }
            $maskingResults = @(Invoke-DbaDbDataMasking @splatMasking)

            # Only the conversion warnings matter here. A table whose only unique index is on an identity column
            # also gets "The table does not have any indexes", which does not stop the masking.
            $WarnVar | Where-Object { "$PSItem" -match "convert" } | Should -BeNullOrEmpty
            $maskingResults.Count | Should -Be 1
            $maskingResults[0].Rows | Should -Be 20

            # Each of the 20 values stays the same by chance with a probability of 1 in 255
            $after = @(Invoke-DbaQuery @splatQuery)
            $changed = @(for ($i = 0; $i -lt $before.Count; $i++) {
                    if ($after[$i].Kon -ne $before[$i].Kon) {
                        $after[$i].Id
                    }
                })
            $changed.Count | Should -BeGreaterThan 0
        }
    }
}