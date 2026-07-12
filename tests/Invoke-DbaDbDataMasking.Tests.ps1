#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbDataMasking",
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
                "FilePath",
                "Locale",
                "CharacterString",
                "Table",
                "Column",
                "ExcludeTable",
                "ExcludeColumn",
                "MaxValue",
                "ModulusFactor",
                "ExactLength",
                "CommandTimeout",
                "BatchSize",
                "Retry",
                "DictionaryFilePath",
                "DictionaryExportPath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "WhatIf behavior" {
        BeforeAll {
            Mock Stop-Function { throw "Stop-Function should not be called during WhatIf unit tests" } -ModuleName dbatools
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Get-DbaRandomizedType {
                [PSCustomObject]@{
                    Type    = "Name"
                    Subtype = "FirstName"
                }
            } -ModuleName dbatools
        }

        BeforeEach {
            $script:lastWhatIfQuery = $null

            $script:mockTables = [PSCustomObject]@{
                Name   = "db1"
                Tables = @(
                    [PSCustomObject]@{
                        Name           = "people"
                        Schema         = "dbo"
                        HasUniqueIndex = $true
                        FilterQuery    = $null
                        Columns        = @(
                            [PSCustomObject]@{
                                Name       = "fname"
                                ColumnType = "varchar"
                                Action     = $null
                                Composite  = $null
                            }
                        )
                    }
                )
            }

            $script:mockTempDbTables = [PSCustomObject]@{
                Name = @()
            }
            $script:mockTempDbTables | Add-Member -MemberType ScriptMethod -Name Refresh -Value { $null } -Force

            $script:mockTempDb = [PSCustomObject]@{
                Tables = $script:mockTempDbTables
            }
            $script:mockTempDb | Add-Member -MemberType ScriptMethod -Name Query -Value {
                param($query)
                $null
            } -Force

            $script:mockIndexes = [PSCustomObject]@{
                Name = @()
            }
            $script:mockIndexes | Add-Member -MemberType ScriptMethod -Name Refresh -Value { $null } -Force

            $script:mockDbTable = [PSCustomObject]@{
                Name    = "people"
                Schema  = "dbo"
                Columns = @(
                    [PSCustomObject]@{
                        Name     = "fname"
                        Identity = $false
                        DataType = "varchar"
                    }
                )
                Indexes = $script:mockIndexes
            }

            $script:mockDatabase = [PSCustomObject]@{
                Name   = "db1"
                Tables = @($script:mockDbTable)
            }
            $script:mockDatabase | Add-Member -MemberType ScriptMethod -Name Query -Value {
                param($query)
                $script:lastWhatIfQuery = $query

                [PSCustomObject]@{
                    RowCount = 2
                }
            } -Force

            $script:mockServer = [PSCustomObject]@{
                VersionMajor = 16
                Databases    = @{
                    tempdb = $script:mockTempDb
                    db1    = $script:mockDatabase
                }
            }

            Mock Invoke-RestMethod { $script:mockTables } -ModuleName dbatools
            Mock Connect-DbaInstance { $script:mockServer } -ModuleName dbatools
            Mock Convert-DbaIndexToTable { [PSCustomObject]@{ } } -ModuleName dbatools
        }

        It "does not prepare unique helper tables when WhatIf is used" {
            $null = Invoke-DbaDbDataMasking -SqlInstance "sql1" -Database "db1" -FilePath "http://masking-config" -WhatIf

            Should -Invoke -CommandName Convert-DbaIndexToTable -Exactly 0 -Scope It -ModuleName dbatools
        }

        It "uses FilterQuery when counting rows for WhatIf" {
            $script:mockTables.Tables[0].HasUniqueIndex = $false
            $script:mockTables.Tables[0].FilterQuery = "SELECT [fname] FROM [dbo].[people] WHERE [fname] LIKE 'J%'"

            $null = Invoke-DbaDbDataMasking -SqlInstance "sql1" -Database "db1" -FilePath "http://masking-config" -WhatIf

            $script:lastWhatIfQuery | Should -Be "SELECT COUNT(*) AS RowCount FROM (SELECT [fname] FROM [dbo].[people] WHERE [fname] LIKE 'J%') AS [dbatools_masking_source]"
        }
    }

    Context "Action filtering" {
        BeforeAll {
            Mock Stop-Function {
                param($Message)
                throw $Message
            } -ModuleName dbatools
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Get-DbaRandomizedType {
                [PSCustomObject]@{
                    Type    = "Name"
                    Subtype = "FirstName"
                }
            } -ModuleName dbatools
            Mock Write-ProgressHelper { } -ModuleName dbatools
        }

        BeforeEach {
            $script:mockTempDbTables = [PSCustomObject]@{
                Name = @()
            }
            $script:mockTempDbTables | Add-Member -MemberType ScriptMethod -Name Refresh -Value { $null } -Force

            $script:mockTempDb = [PSCustomObject]@{
                Tables = $script:mockTempDbTables
            }
            $script:mockTempDb | Add-Member -MemberType ScriptMethod -Name Query -Value {
                param($query)
                $null
            } -Force

            $script:mockIndexes = [PSCustomObject]@{
                Name = @()
            }
            $script:mockIndexes | Add-Member -MemberType ScriptMethod -Name Refresh -Value { $null } -Force

            $script:mockDbTable = [PSCustomObject]@{
                Name    = "people"
                Schema  = "dbo"
                Columns = @(
                    [PSCustomObject]@{
                        Name     = "PersonId"
                        Identity = $true
                        DataType = "int"
                    },
                    [PSCustomObject]@{
                        Name     = "fname"
                        Identity = $false
                        DataType = "varchar"
                    }
                )
                Indexes = $script:mockIndexes
            }

            $script:mockServer = [DbaInstanceParameter]"sql1"
            $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "sql1"
            $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
            $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "sql1"
            $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name VersionMajor -Value 16

            $script:mockDatabase = [PSCustomObject]@{
                Name   = "db1"
                Parent = $script:mockServer
                Tables = @($script:mockDbTable)
            }
            $script:mockDatabase | Add-Member -MemberType ScriptMethod -Name Query -Value {
                param($query)
                @(
                    [PSCustomObject]@{
                        PersonId = 1
                        fname    = "Joe"
                    }
                )
            } -Force

            $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name Databases -Value @{
                tempdb = $script:mockTempDb
                db1    = $script:mockDatabase
            }

            $script:mockTables = [PSCustomObject]@{
                Name   = "db1"
                Tables = @(
                    [PSCustomObject]@{
                        Name           = "people"
                        Schema         = "dbo"
                        HasUniqueIndex = $false
                        FilterQuery    = "SELECT TOP 1 [fname] FROM [dbo].[people] ORDER BY [fname]"
                        Columns        = @(
                            [PSCustomObject]@{
                                Name       = "fname"
                                ColumnType = "varchar"
                                Nullable   = $true
                                Action     = [PSCustomObject]@{
                                    Category = "Column"
                                    Type     = "Set"
                                    Value    = "masked"
                                }
                                Composite  = $null
                            }
                        )
                    }
                )
            }

            Mock Invoke-RestMethod { $script:mockTables } -ModuleName dbatools
            Mock Connect-DbaInstance { $script:mockServer } -ModuleName dbatools
            Mock Invoke-DbaQuery { } -ModuleName dbatools
        }

        It "uses the filtered row set when building action updates" {
            $null = Invoke-DbaDbDataMasking -SqlInstance "sql1" -Database "db1" -FilePath "http://masking-config"

            Should -Invoke -CommandName Invoke-DbaQuery -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                $Query.Trim() -eq "UPDATE [dbo].[people] SET [fname] = 'masked' WHERE [PersonId] IN (1);"
            }
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create unique temporary path for masking config files
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory

        $dbName = "dbatoolsci_masker"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL,
                    [percenttest] [decimal](15,3) NULL,
                    [bittest] bit NULL
                ) ON [PRIMARY]
                GO
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Joe','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Jane','Schmee','2/2/1950',65.38,0)
                GO
                CREATE TABLE [dbo].[people2](
                                    [fname] [varchar](50) NULL,
                                    [lname] [varchar](50) NULL,
                                    [dob] [datetime] NULL,
                                    [percenttest] [decimal](15,3) NULL,
                                    [bittest] bit NULL
                                ) ON [PRIMARY]
                GO
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Layla','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Eric','Schmee','2/2/1950',65.38,0)"

        $splatDatabase = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $dbName
        }
        $null = New-DbaDatabase @splatDatabase

        $splatQuery = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
            Query       = $sql
        }
        $null = Invoke-DbaQuery @splatQuery

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveDb = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
        }
        $null = Remove-DbaDatabase @splatRemoveDb -ErrorAction SilentlyContinue

        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "starts with the right data" {
            $splatQuery1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where fname = 'Joe'"
            }
            Invoke-DbaQuery @splatQuery1 | Should -Not -Be $null

            $splatQuery2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuery2 | Should -Not -Be $null

            $splatQuery3 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 29.53"
            }
            Invoke-DbaQuery @splatQuery3 | Should -Not -Be $null

            $splatQuery4 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 65.38"
            }
            Invoke-DbaQuery @splatQuery4 | Should -Not -Be $null

            $splatQuery5 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 1 AND lname = 'Schmoe'"
            }
            Invoke-DbaQuery @splatQuery5 | Should -Not -Be $null

            $splatQuery6 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 0 AND lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuery6 | Should -Not -Be $null
        }

        It "returns the proper output" {
            $splatConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Path        = $tempPath
            }
            $configFile = New-DbaDbMaskingConfig @splatConfig

            $splatMasking = @{
                FilePath    = $configFile.FullName
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
            }
            $results = @(Invoke-DbaDbDataMasking @splatMasking)

            $results[0].Rows | Should -Be 2
            $results[0].Database | Should -Contain $dbName

            $results[1].Rows | Should -Be 2
            $results[1].Database | Should -Contain $dbName
        }

        It "masks the data and does not delete it" {
            $splatQueryAll = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people"
            }
            Invoke-DbaQuery @splatQueryAll | Should -Not -Be $null

            $splatQueryJoe = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where fname = 'Joe'"
            }
            Invoke-DbaQuery @splatQueryJoe | Should -Be $null

            $splatQuerySchmee = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuerySchmee | Should -Be $null

            $splatQueryPercent1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 29.53"
            }
            Invoke-DbaQuery @splatQueryPercent1 | Should -Be $null

            $splatQueryPercent2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 65.38"
            }
            Invoke-DbaQuery @splatQueryPercent2 | Should -Be $null

            $splatQueryBit1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 1 AND lname = 'Schmoe'"
            }
            Invoke-DbaQuery @splatQueryBit1 | Should -Be $null

            $splatQueryBit2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 0 AND lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQueryBit2 | Should -Be $null
        }

    }
}