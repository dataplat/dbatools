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

    Context "When a table of deterministic values is left over" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $leftoverPath = "$tempPath\leftover"
            $null = New-Item -Path $leftoverPath -ItemType Directory
            $splatLeftoverConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Path        = $leftoverPath
            }
            $leftoverConfigFile = New-DbaDbMaskingConfig @splatLeftoverConfig
            # A run that ended early left its table behind. The command drops it first, and the drop used to put a $null
            # into the output before the results.
            $splatLeftoverTable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Query       = "IF OBJECT_ID(N'dbo.DeterministicValues') IS NULL CREATE TABLE dbo.DeterministicValues ([ValueKey] VARCHAR(900), [NewValue] VARCHAR(900))"
            }
            $null = Invoke-DbaQuery @splatLeftoverTable
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatLeftoverMasking = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FilePath    = $leftoverConfigFile.FullName
            }
            $leftoverResults = @(Invoke-DbaDbDataMasking @splatLeftoverMasking)
            $leftoverWarning = $WarnVar
        }

        It "Returns one result per table and nothing else" {
            $leftoverWarning | Should -BeNullOrEmpty
            $leftoverResults.Count | Should -Be 2
            $leftoverResults.Table | Should -Be @("people", "people2")
        }
    }

    Context "When a column of the config has a composite" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $compositePath = "$tempPath\composite"
            $null = New-Item -Path $compositePath -ItemType Directory
            $splatCompositeConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "people"
                Path        = $compositePath
            }
            $compositeConfigFile = New-DbaDbMaskingConfig @splatCompositeConfig
            $compositeConfig = Get-Content -Path $compositeConfigFile.FullName -Raw | ConvertFrom-Json
            $compositeColumn = $compositeConfig.Tables[0].Columns | Where-Object Name -eq "lname"
            $compositeColumn.Composite = @(
                [PSCustomObject]@{ Type = "Column"; Value = "fname" },
                [PSCustomObject]@{ Type = "Static"; Value = "-composite" }
            )
            $compositeConfigPath = "$compositePath\composite.json"
            $compositeConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $compositeConfigPath
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The UPDATE statements of the composites used to be written to the pipeline before they were run.
            $splatCompositeMasking = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FilePath    = $compositeConfigPath
            }
            $compositeResults = @(Invoke-DbaDbDataMasking @splatCompositeMasking)
            $compositeWarning = $WarnVar
        }

        It "Returns only the result of the table" {
            $compositeWarning | Should -BeNullOrEmpty
            $compositeResults.Count | Should -Be 1
            $compositeResults[0].Table | Should -Be "people"
        }

        It "Fills the column from the composite" {
            $splatCompositeData = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT fname, lname FROM dbo.people"
            }
            foreach ($row in (Invoke-DbaQuery @splatCompositeData)) {
                $row.lname | Should -Be "$($row.fname)-composite"
            }
        }
    }

    Context "When an action of the config fails" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $actionPath = "$tempPath\action"
            $null = New-Item -Path $actionPath -ItemType Directory
            $splatActionConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "people"
                Path        = $actionPath
            }
            $actionConfigFile = New-DbaDbMaskingConfig @splatActionConfig
            $actionConfig = Get-Content -Path $actionConfigFile.FullName -Raw | ConvertFrom-Json
            # A division by zero makes the UPDATE of the action fail on the server.
            $actionColumn = $actionConfig.Tables[0].Columns | Where-Object Name -eq "percenttest"
            $actionColumn.Action = [PSCustomObject]@{
                Category = "Number"
                Type     = "Divide"
                Value    = 0
            }
            $actionConfigPath = "$actionPath\action.json"
            $actionConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $actionConfigPath
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The failed UPDATE statements used to be written to the pipeline, and the -Continue after the warning skipped
            # the removal of the identity column and the index the command had added to the table.
            $splatActionMasking = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $dbName
                FilePath      = $actionConfigPath
                WarningAction = "SilentlyContinue"
            }
            $actionResults = @(Invoke-DbaDbDataMasking @splatActionMasking)
            $actionWarning = $WarnVar
        }

        It "Warns about the failed update and returns nothing" {
            ($actionWarning -join " ") | Should -BeLike "*Error updating dbo.people*"
            $actionResults | Should -BeNullOrEmpty
        }

        It "Removes the identity column and the index it added" {
            $splatActionLeftover = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT (SELECT COUNT(*) FROM sys.columns WHERE name = N'MaskingID') + (SELECT COUNT(*) FROM sys.indexes WHERE name LIKE N'NIX[_][_]%[_]Masking') AS Leftovers"
            }
            (Invoke-DbaQuery @splatActionLeftover).Leftovers | Should -Be 0
        }
    }

    Context "When a table of the config has composites and actions" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $bothPath = "$tempPath\both"
            $null = New-Item -Path $bothPath -ItemType Directory
            $splatBothConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "people2"
                Path        = $bothPath
            }
            $bothConfigFile = New-DbaDbMaskingConfig @splatBothConfig
            $bothConfig = Get-Content -Path $bothConfigFile.FullName -Raw | ConvertFrom-Json
            $bothCompositeColumn = $bothConfig.Tables[0].Columns | Where-Object Name -eq "lname"
            $bothCompositeColumn.Composite = @(
                [PSCustomObject]@{ Type = "Static"; Value = "composite" }
            )
            $bothActionColumn = $bothConfig.Tables[0].Columns | Where-Object Name -eq "percenttest"
            $bothActionColumn.Action = [PSCustomObject]@{
                Category = "Number"
                Type     = "Add"
                Value    = 1
            }
            $bothConfigPath = "$bothPath\both.json"
            $bothConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $bothConfigPath
            $splatBothData = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT fname, lname, dob, percenttest, bittest FROM dbo.people2 ORDER BY fname"
                As          = "PSObject"
            }
            $bothDataBefore = Invoke-DbaQuery @splatBothData | ConvertTo-Json -Compress
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command warned that it cannot use both and then masked the table anyway.
            $splatBothMasking = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $dbName
                FilePath      = $bothConfigPath
                WarningAction = "SilentlyContinue"
            }
            $bothResults = @(Invoke-DbaDbDataMasking @splatBothMasking)
            $bothWarning = $WarnVar
            $bothDataAfter = Invoke-DbaQuery @splatBothData | ConvertTo-Json -Compress
        }

        It "Warns and returns nothing" {
            ($bothWarning -join " ") | Should -BeLike "*You cannot use both composites and actions*"
            $bothResults | Should -BeNullOrEmpty
        }

        It "Leaves the data of the table as it was" {
            $bothDataAfter | Should -Be $bothDataBefore
        }

        It "Removes the identity column and the index it added" {
            $splatBothLeftover = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT (SELECT COUNT(*) FROM sys.columns WHERE name = N'MaskingID') + (SELECT COUNT(*) FROM sys.indexes WHERE name LIKE N'NIX[_][_]%[_]Masking') AS Leftovers"
            }
            (Invoke-DbaQuery @splatBothLeftover).Leftovers | Should -Be 0
        }
    }

    Context "When the pipeline is stopped" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatStopConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Path        = $tempPath
            }
            $stopConfigFile = New-DbaDbMaskingConfig @splatStopConfig
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The pipeline is stopped as soon as the first
            # masking record arrives, which is what Ctrl+C does. The runspace imports the manifest: an import of the
            # psm1 without a command line skips the type data, and without it SMO databases have no Query method.
            $splatStopMasking = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FilePath    = $stopConfigFile.FullName
                Confirm     = $false
            }
            if ($TestConfig.SqlCred) {
                $splatStopMasking.SqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("Invoke-DbaDbDataMasking").AddParameters($splatStopMasking)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($stopShell.Streams.Progress | Where-Object Activity -like "Masking *") -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        AfterAll {
            # The stopped run did not get to drop its table of deterministic values.
            # It drops it in a finally now. The drop here keeps a regression from leaving the table to the next test file.
            $splatDropValues = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "tempdb"
                Query           = "IF OBJECT_ID(N'dbo.DeterministicValues') IS NOT NULL DROP TABLE dbo.DeterministicValues"
                EnableException = $true
            }
            $null = Invoke-DbaQuery @splatDropValues
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -like "Masking *" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }

        It "Drops its table of deterministic values" {
            $splatValuesTable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Query       = "SELECT COUNT(*) AS ValuesTables FROM sys.tables WHERE name = N'DeterministicValues'"
            }
            (Invoke-DbaQuery @splatValuesTable).ValuesTables | Should -Be 0
        }

        It "Removes the identity column and the index it added" {
            $splatStopLeftover = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT (SELECT COUNT(*) FROM sys.columns WHERE name = N'MaskingID') + (SELECT COUNT(*) FROM sys.indexes WHERE name LIKE N'NIX[_][_]%[_]Masking') AS Leftovers"
            }
            (Invoke-DbaQuery @splatStopLeftover).Leftovers | Should -Be 0
        }
    }
}