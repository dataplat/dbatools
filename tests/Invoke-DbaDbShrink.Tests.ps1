#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbShrink",
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
                "AllUserDatabases",
                "PercentFreeSpace",
                "ShrinkMethod",
                "FileType",
                "StepSize",
                "StatementTimeout",
                "WaitAtLowPriority",
                "AbortAfterWait",
                "ExcludeIndexStats",
                "ExcludeUpdateUsage",
                "EnableException",
                "InputObject"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Failure output handling" {
            BeforeEach {
                $script:warningMessages = @()

                function New-MockShrinkDatabase {
                    $dataFile = [PSCustomObject]@{
                        Name      = "testdb"
                        Size      = 1024
                        UsedSpace = 512
                    }
                    $dataFile | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }

                    $server = [PSCustomObject]@{
                        ComputerName       = "sql1"
                        ServiceName        = "MSSQLSERVER"
                        DomainInstanceName = "sql1"
                        VersionMajor       = 16
                        ConnectionContext  = [PSCustomObject]@{
                            StatementTimeout = 0
                        }
                    }

                    $server | Add-Member -MemberType ScriptMethod -Name Query -Value {
                        param($Sql, $DatabaseName)

                        if ($Sql -like "DBCC SHRINKFILE*") {
                            throw "simulated shrink failure"
                        }

                        @()
                    }

                    $database = New-Object Microsoft.SqlServer.Management.Smo.Database
                    $database.Name = "testdb"
                    $database | Add-Member -Force -NotePropertyName IsAccessible -NotePropertyValue $true
                    $database | Add-Member -Force -NotePropertyName IsDatabaseSnapshot -NotePropertyValue $false
                    $database | Add-Member -Force -NotePropertyName Parent -NotePropertyValue $server
                    $database | Add-Member -Force -NotePropertyName FileGroups -NotePropertyValue ([PSCustomObject]@{
                            Files = @($dataFile)
                        })
                    $database | Add-Member -Force -NotePropertyName LogFiles -NotePropertyValue @()

                    $database
                }

                function Test-FunctionInterrupt {
                    $false
                }

                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        $ExcludeProperty
                    )

                    process {
                        $InputObject
                    }
                }

                function Write-Message {
                    param(
                        $Level,
                        $Message,
                        $ErrorRecord,
                        $EnableException
                    )

                    if ($Level -eq "Warning") {
                        $script:warningMessages += $Message
                    }
                }

                Mock Stop-Function -ModuleName dbatools { }
            }

            It "returns a failed result and warning without calling Stop-Function in friendly mode" {
                $mockDatabase = New-MockShrinkDatabase

                $results = @(Invoke-DbaDbShrink -InputObject $mockDatabase -FileType Data -ExcludeIndexStats)

                $results | Should -HaveCount 1
                $results[0].Success | Should -Be $false
                $results[0].Notes | Should -Match "simulated shrink failure"
                ($script:warningMessages -join " ") | Should -Match "Shrink operation failed for file testdb: .*simulated shrink failure"
                Assert-MockCalled -CommandName Stop-Function -Exactly 0 -Scope It
            }

            It "still uses Stop-Function when EnableException is requested" {
                $mockDatabase = New-MockShrinkDatabase

                Mock Stop-Function -ModuleName dbatools {
                    throw $Message
                }

                {
                    Invoke-DbaDbShrink -InputObject $mockDatabase -FileType Data -ExcludeIndexStats -EnableException
                } | Should -Throw "*Shrink operation failed for file testdb:*simulated shrink failure*"

                Assert-MockCalled -CommandName Stop-Function -Exactly 1 -Scope It
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $defaultPath = $server | Get-DbaDefaultPath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying Database is shrunk" {
        BeforeEach {
            # Create Database with small size and grow it
            $db = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_shrinktest")

            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($db, "PRIMARY")
            $db.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryFileGroup, $db.Name)
            $primaryFile.FileName = "$($defaultPath.Data)\$($db.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 8 * 1024
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile($db, "$($db.Name)_log")
            $logFile.FileName = "$($defaultPath.Log)\$($db.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 8 * 1024
            $logFile.GrowthType = "KB"
            $db.LogFiles.Add($logFile)

            $db.Create()

            # grow the files
            $server.Query("
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)', SIZE = 16384KB )
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)_log', SIZE = 16384KB )")

            # Save the current file sizes
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $oldLogSize = $db.LogFiles[0].Size
            $oldDataSize = $db.FileGroups[0].Files[0].Size
            $db.Checkpoint()
        }
        AfterEach {
            $db | Remove-DbaDatabase
        }

        It "Shrinks just the log file when FileType is Log" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Log
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be "$($db.Name)_log"
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -Be $oldDataSize
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
        }

        It "Shrinks just the data file(s) when FileType is Data" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Shrinks the entire database when FileType is All" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType All
            $result.Database | Should -Be $db.Name, $db.Name
            $result.File | Should -Be "$($db.Name)_log", $db.Name
            $result.Success | Should -Be $true, $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
        }

        It "Shrinks just the data file(s) when FileType is Data and uses the StepSize" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data -StepSize 2MB
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Accepts pipelined databases (see #9495)" {
            $result = $db | Invoke-DbaDbShrink -FileType Data
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Shrinks with WaitAtLowPriority on SQL Server 2022+" {
            if ($server.VersionMajor -lt 16) {
                Set-ItResult -Skipped -Because "Test is only for SQL Server 2022 and later"
                return
            }

            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data -WaitAtLowPriority -AbortAfterWait Self
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
        }

        It "Verifies WAIT_AT_LOW_PRIORITY SQL syntax appears in running requests when blocked" {
            if ($server.VersionMajor -lt 16) {
                Set-ItResult -Skipped -Because "Test is only for SQL Server 2022 and later"
                return
            }

            # Create a table with data so DBCC SHRINKFILE will need to acquire locks when moving pages
            $null = $server.Query("USE [$($db.Name)]; CREATE TABLE dbo.dbatoolsci_shrink_blocker (c1 INT); INSERT INTO dbo.dbatoolsci_shrink_blocker SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns a1 CROSS JOIN sys.all_columns a2")

            # Start a job that holds an exclusive table lock to force the shrink to wait at low priority
            $blockConnStr = $server.ConnectionContext.ConnectionString
            $blockDbName = $db.Name
            $blockJob = Start-Job -ScriptBlock {
                param($connStr, $dbName, $blockDuration)
                $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandTimeout = 60
                $cmd.CommandText = "USE [$dbName]; BEGIN TRAN; SELECT TOP 1 c1 FROM dbo.dbatoolsci_shrink_blocker WITH (TABLOCKX, HOLDLOCK); WAITFOR DELAY '$blockDuration'; IF @@TRANCOUNT > 0 ROLLBACK TRAN"
                try { $cmd.ExecuteNonQuery() } catch { }
                $conn.Close()
            } -ArgumentList $blockConnStr, $blockDbName, "00:00:45"

            Start-Sleep -Seconds 2

            # Start the shrink with WAIT_AT_LOW_PRIORITY in a background job
            $shrinkServerName = $server.DomainInstanceName
            $shrinkDbName = $db.Name
            $shrinkModulePath = (Get-Module dbatools | Select-Object -First 1).Path
            $shrinkJob = Start-Job -ScriptBlock {
                param($modulePath, $serverName, $dbName)
                Import-Module $modulePath
                Invoke-DbaDbShrink -SqlInstance $serverName -Database $dbName -FileType Data -WaitAtLowPriority
            } -ArgumentList $shrinkModulePath, $shrinkServerName, $shrinkDbName

            # Verify the SQL text of the running shrink request contains WAIT_AT_LOW_PRIORITY
            $sqlTextCount = 0
            for ($i = 1; $i -le 45; $i++) {
                Start-Sleep -Seconds 1
                $sqlTextCount = ($server.Query("SELECT COUNT(*) AS C FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE t.text LIKE '%WAIT_AT_LOW_PRIORITY%'")).C
                if ($sqlTextCount -gt 0) {
                    break
                }
            }

            $null = $blockJob | Wait-Job -Timeout 60
            $blockJob | Remove-Job -Force
            $null = $shrinkJob | Wait-Job -Timeout 90
            $shrinkJob | Remove-Job -Force

            $sqlTextCount | Should -BeGreaterThan 0
        }

        It "Returns an error when WaitAtLowPriority is used on SQL Server older than 2022" {
            if ($server.VersionMajor -ge 16) {
                Set-ItResult -Skipped -Because "Test is only for SQL Server 2019 and older"
                return
            }
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data -WaitAtLowPriority -WarningAction SilentlyContinue
            $WarnVar | Should -Match "SQL Server 2022"
        }
    }
}