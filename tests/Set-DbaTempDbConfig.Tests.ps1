#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaTempDbConfig",
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
                "DataFileCount",
                "DataFileSize",
                "LogFileSize",
                "DataFileGrowth",
                "LogFileGrowth",
                "DataPath",
                "LogPath",
                "OutFile",
                "OutputScriptOnly",
                "DisableGrowth",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $tempdbDataFilePhysicalName = $server.Databases["tempdb"].Query("SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1").PhysicalName
        $tempdbDataFilePath = Split-Path $tempdbDataFilePhysicalName

        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            $null = New-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\Log_$random" -Type Directory
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock {
                $null = New-Item -Path "$($args[0])\DataDir0_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\DataDir1_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\DataDir2_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\Log_$($args[1])" -Type Directory
            } -ArgumentList $tempdbDataFilePath, $random
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created directories.
        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            Remove-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\Log_$random" -Force -ErrorAction SilentlyContinue
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock {
                Remove-Item -Path "$($args[0])\DataDir0_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\DataDir1_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\DataDir2_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\Log_$($args[1])" -Force -ErrorAction SilentlyContinue
            } -ArgumentList $tempdbDataFilePath, $random
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {

        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileSize 1024 -DataPath "$tempdbDataFilePath\invalidDir_$random" -OutputScriptOnly -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "does not exist"
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 2048 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$tempdbDataFilePath\DataDir0_$random" -LogPath "$tempdbDataFilePath\Log_$random" -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=256 MB,filegrowth=1024" -and $PSItem -Match "DataDir0_$random" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=512" -and $PSItem -Match "Log_$random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $tempdbDataFilePath -LogPath $tempdbDataFilePath -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=0" -and $PSItem -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$tempdbDataFilePath\DataDir0_$random", "$tempdbDataFilePath\DataDir1_$random", "$tempdbDataFilePath\DataDir2_$random"
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 1024 -DataPath $dataDirLocations -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            # check the round robin assignment of files to data dir locations
            $indexToUse = 0
            foreach ($sqlStatement in $sqlStatements) {
                ($sqlStatement -Match "DataDir$indexToUse" -or $sqlStatement -Match "log") | Should -Be $true

                $indexToUse += 1
                if ($indexToUse -ge $dataDirLocations.Count) {
                    $indexToUse = 0
                }
            }
        }
    }

    Context "Reducing the tempdb data file count against a real instance" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $tempdbReductionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $tempdbReductionPhysicalName = $tempdbReductionServer.Databases["tempdb"].Query("SELECT physical_name AS PhysicalName FROM sys.database_files WHERE file_id = 1").PhysicalName
            $tempdbReductionDataPath = Split-Path $tempdbReductionPhysicalName
            $originalDataFileState = @($tempdbReductionServer.Databases["tempdb"].Query("SELECT file_id AS ID, name AS LogicalName, size AS SizePages, growth AS GrowthValue, is_percent_growth AS IsPercentGrowth FROM sys.database_files WHERE type = 0 ORDER BY file_id"))
            $originalLogFileState = $tempdbReductionServer.Databases["tempdb"].Query("SELECT name AS LogicalName, size AS SizePages FROM sys.database_files WHERE type = 1")
            $originalDataFiles = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0)
            $originalDataFileCount = $originalDataFiles.Count
            $expandedDataFileCount = $originalDataFileCount + 2
            $largestDataFileSize = ($originalDataFiles | ForEach-Object { [Math]::Ceiling($PSItem.Size.Megabyte) } | Measure-Object -Maximum).Maximum
            $individualDataFileSize = [Math]::Max(64, [int]$largestDataFileSize)
            $expandedTotalDataFileSize = $individualDataFileSize * $expandedDataFileCount
            $allocationTableName = "dbatoolsci_tempdb_reduction_$(Get-Random)"
            $allocationRowCount = 15000

            # A connection of its own that starts in msdb, so the tests can assert that the command puts the
            # database of the caller back. It has to be non-pooled: SMO reopens a pooled connection at its
            # default database, which hides the leak. msdb rather than master, because restoring to master
            # would pass an assertion and still be wrong. See #10555.
            $tempdbContextServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb -NonPooledConnection

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($null -ne $tempdbContextServer) {
                $null = $tempdbContextServer | Disconnect-DbaInstance
            }

            if ($null -ne $tempdbReductionServer -and $null -ne $allocationTableName) {
                $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery("IF OBJECT_ID(N'dbo.$allocationTableName', N'U') IS NOT NULL DROP TABLE dbo.[$allocationTableName];")
            }

            # Restore the original tempdb data file count in case an assertion above failed midway.
            if ($null -ne $originalDataFileCount -and $null -ne $expandedTotalDataFileSize) {
                $currentDataFileCount = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0).Count
                $restoreAttempt = 0
                $restoreError = $null
                while ($currentDataFileCount -ne $originalDataFileCount -and $restoreAttempt -lt 3) {
                    $restoreAttempt += 1
                    $splatRestore = @{
                        SqlInstance   = $tempdbReductionServer
                        DataFileCount = $originalDataFileCount
                        DataFileSize  = $expandedTotalDataFileSize
                        DataPath      = $tempdbReductionDataPath
                        Force         = $true
                        Confirm       = $false
                    }
                    try {
                        $null = Set-DbaTempDbConfig @splatRestore
                        $restoreError = $null
                    } catch {
                        $restoreError = $PSItem
                    }
                    $currentDataFileCount = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0).Count
                }

                if ($currentDataFileCount -gt $originalDataFileCount) {
                    $originalLogicalNames = @($originalDataFiles.LogicalName)
                    $extraDataFiles = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object { $PSItem.Type -eq 0 -and $PSItem.LogicalName -notin $originalLogicalNames } | Sort-Object ID -Descending)
                    foreach ($extraDataFile in $extraDataFiles) {
                        $escapedExtraLogicalName = $extraDataFile.LogicalName.Replace("'", "''")
                        $escapedExtraIdentifier = $extraDataFile.LogicalName.Replace("]", "]]")
                        # The cache release makes the removal possible, but a fresh work table can appear in
                        # the file between two removals, so every file gets up to three attempts.
                        $extraRemovalAttempt = 0
                        do {
                            $extraRemovalAttempt += 1
                            try {
                                $tempdbReductionServer.Databases["master"].ExecuteNonQuery("DBCC FREESYSTEMCACHE ('ALL'); USE [tempdb]; DBCC SHRINKFILE (N'$escapedExtraLogicalName', EMPTYFILE); ALTER DATABASE tempdb REMOVE FILE [$escapedExtraIdentifier];")
                                $extraRemovalError = $null
                            } catch {
                                $extraRemovalError = $PSItem
                                Start-Sleep -Seconds 2
                            }
                        } while ($extraRemovalError -and $extraRemovalAttempt -lt 3)
                        if ($extraRemovalError) {
                            throw $extraRemovalError
                        }
                    }
                    $currentDataFileCount = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0).Count
                }

                if ($currentDataFileCount -ne $originalDataFileCount) {
                    throw "Failed to restore tempdb to $originalDataFileCount data files after $restoreAttempt attempts. Last error: $restoreError"
                }

                foreach ($originalDataFile in $originalDataFileState) {
                    $escapedOriginalLogicalName = $originalDataFile.LogicalName.Replace("'", "''")
                    $originalSizeMb = [Math]::Max(1, [Math]::Floor($originalDataFile.SizePages / 128.0))
                    $originalSizeKb = $originalDataFile.SizePages * 8
                    if ($originalDataFile.GrowthValue -eq 0) {
                        $originalGrowthSetting = "0"
                    } elseif ($originalDataFile.IsPercentGrowth) {
                        $originalGrowthSetting = "$($originalDataFile.GrowthValue)%"
                    } else {
                        $originalGrowthSetting = "$($originalDataFile.GrowthValue * 8)KB"
                    }

                    $sizeRestoreAttempt = 0
                    do {
                        $sizeRestoreAttempt += 1
                        $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery("DBCC FREESYSTEMCACHE ('ALL'); DBCC SHRINKFILE (N'$escapedOriginalLogicalName', $originalSizeMb);")
                        $restoredSizePages = $tempdbReductionServer.Databases["tempdb"].Query("SELECT size AS SizePages FROM sys.database_files WHERE file_id = $($originalDataFile.ID)").SizePages
                    } while ($restoredSizePages -gt $originalDataFile.SizePages -and $sizeRestoreAttempt -lt 3)

                    if ($restoredSizePages -lt $originalDataFile.SizePages) {
                        $tempdbReductionServer.Databases["master"].ExecuteNonQuery("ALTER DATABASE tempdb MODIFY FILE (NAME = N'$escapedOriginalLogicalName', SIZE = $($originalSizeKb)KB);")
                    }
                    $tempdbReductionServer.Databases["master"].ExecuteNonQuery("ALTER DATABASE tempdb MODIFY FILE (NAME = N'$escapedOriginalLogicalName', FILEGROWTH = $originalGrowthSetting);")

                    if ($restoredSizePages -gt $originalDataFile.SizePages) {
                        throw "Failed to shrink tempdb file $($originalDataFile.LogicalName) to its original size after $sizeRestoreAttempt attempts."
                    }
                }

                $restoredDataFileState = @($tempdbReductionServer.Databases["tempdb"].Query("SELECT file_id AS ID, name AS LogicalName, size AS SizePages, growth AS GrowthValue, is_percent_growth AS IsPercentGrowth FROM sys.database_files WHERE type = 0 ORDER BY file_id"))
                foreach ($originalDataFile in $originalDataFileState) {
                    $restoredDataFile = $restoredDataFileState | Where-Object ID -eq $originalDataFile.ID
                    if ($restoredDataFile.SizePages -ne $originalDataFile.SizePages -or $restoredDataFile.GrowthValue -ne $originalDataFile.GrowthValue -or $restoredDataFile.IsPercentGrowth -ne $originalDataFile.IsPercentGrowth) {
                        throw "Failed to restore tempdb file $($originalDataFile.LogicalName) to its original size and growth settings."
                    }
                }
            }

            # The allocation table grows the tempdb log through normal autogrowth and no command
            # call puts it back, so the original size is restored explicitly.
            if ($null -ne $originalLogFileState) {
                $escapedLogLogicalName = $originalLogFileState.LogicalName.Replace("'", "''")
                $originalLogSizeMb = [Math]::Max(1, [Math]::Floor($originalLogFileState.SizePages / 128.0))
                $logRestoreAttempt = 0
                do {
                    $logRestoreAttempt += 1
                    $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery("DBCC FREESYSTEMCACHE ('ALL'); DBCC SHRINKFILE (N'$escapedLogLogicalName', $originalLogSizeMb);")
                    $restoredLogSizePages = $tempdbReductionServer.Databases["tempdb"].Query("SELECT size AS SizePages FROM sys.database_files WHERE name = N'$escapedLogLogicalName'").SizePages
                } while ($restoredLogSizePages -gt $originalLogFileState.SizePages -and $logRestoreAttempt -lt 3)

                if ($restoredLogSizePages -lt $originalLogFileState.SizePages) {
                    $tempdbReductionServer.Databases["master"].ExecuteNonQuery("ALTER DATABASE tempdb MODIFY FILE (NAME = N'$escapedLogLogicalName', SIZE = $($originalLogFileState.SizePages * 8)KB);")
                }
                if ($restoredLogSizePages -gt $originalLogFileState.SizePages) {
                    throw "Failed to shrink the tempdb log file back to its original size after $logRestoreAttempt attempts."
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "adds real files and safely force-removes the highest file ids" {
            $splatExpand = @{
                SqlInstance     = $tempdbReductionServer
                DataFileCount   = $expandedDataFileCount
                DataFileSize    = $expandedTotalDataFileSize
                DataPath        = $tempdbReductionDataPath
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                EnableException = $true
            }
            $expandResult = Set-DbaTempDbConfig @splatExpand
            $expandResult.DataFileCount | Should -Be $expandedDataFileCount

            $expandedFiles = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0)
            $expandedFiles.Count | Should -Be $expandedDataFileCount

            $highestFile = $expandedFiles | Where-Object ID -ne 1 | Sort-Object ID -Descending | Select-Object -First 1
            $specialLogicalName = "dbatoolsci_tempdb_'file]_$($highestFile.ID)%"
            $escapedCurrentName = $highestFile.LogicalName.Replace("'", "''")
            $escapedSpecialName = $specialLogicalName.Replace("'", "''")
            $tempdbReductionServer.Databases["master"].ExecuteNonQuery("ALTER DATABASE tempdb MODIFY FILE (NAME = N'$escapedCurrentName', NEWNAME = N'$escapedSpecialName');")

            $allocationQuery = @"
CREATE TABLE dbo.[$allocationTableName] (Payload char(8000) NOT NULL);
INSERT dbo.[$allocationTableName] (Payload)
SELECT TOP ($allocationRowCount) REPLICATE('x', 8000)
FROM sys.all_objects AS first_source
CROSS JOIN sys.all_objects AS second_source;
"@
            $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery($allocationQuery)

            $expandedFiles = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0)
            $expectedRemovedFiles = @($expandedFiles | Where-Object ID -ne 1 | Sort-Object ID -Descending | Select-Object -First 2)
            $fileUsage = @($tempdbReductionServer.Databases["tempdb"].Query("SELECT file_id AS ID, FILEPROPERTY(name, 'SpaceUsed') / 128.0 AS UsedMb FROM sys.database_files WHERE type = 0"))
            foreach ($expectedRemovedFile in $expectedRemovedFiles) {
                ($fileUsage | Where-Object ID -eq $expectedRemovedFile.ID).UsedMb | Should -BeGreaterThan 0
            }

            $withoutForceWarning = $null
            $withoutForceResult = Set-DbaTempDbConfig -SqlInstance $tempdbReductionServer -DataFileCount $originalDataFileCount -DataFileSize $expandedTotalDataFileSize -OutputScriptOnly -WarningVariable withoutForceWarning -WarningAction SilentlyContinue
            $withoutForceResult | Should -BeNullOrEmpty
            ($withoutForceWarning -join " ") | Should -Match "greater number of files"

            $tempdbUsedMb = $tempdbReductionServer.Databases["tempdb"].Query("SELECT SUM(FILEPROPERTY(name, 'SpaceUsed')) / 128.0 AS UsedMb FROM sys.database_files WHERE type = 0").UsedMb
            $insufficientDataFileSize = [Math]::Max(1, [Math]::Floor($tempdbUsedMb / 2))
            $capacityWarning = $null
            $capacityResult = Set-DbaTempDbConfig -SqlInstance $tempdbReductionServer -DataFileCount $originalDataFileCount -DataFileSize $insufficientDataFileSize -Force -OutputScriptOnly -WarningVariable capacityWarning -WarningAction SilentlyContinue
            $capacityResult | Should -BeNullOrEmpty
            ($capacityWarning -join " ") | Should -Match "exceeds the requested target capacity"

            # Seed cached work tables. They survive the queries that created them, are allocated into the
            # emptiest files - exactly the files the reduction is about to remove - and EMPTYFILE cannot
            # move their pages. On an instance with a warm cache this is what made the reduction fail, so
            # it is made deterministic here: without the cache release in the command, the reduction fails.
            $seedWorkTablesQuery = @"
DECLARE @i int = 0, @sql nvarchar(max);
WHILE @i < 40
BEGIN
    SET @sql = N'DECLARE cur CURSOR STATIC FOR SELECT TOP (' + CAST(1000 + @i AS nvarchar(10)) + N') name FROM sys.all_objects ORDER BY NEWID(); OPEN cur; CLOSE cur; DEALLOCATE cur;';
    EXEC sp_executesql @sql;
    SET @i += 1;
END
"@
            $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery($seedWorkTablesQuery)

            # The reduction below passes no log related parameter, so the log file has to stay
            # untouched. This guards against the log statement that every call used to emit, which
            # silently reset the growth of the log file to the LogFileGrowth default of 512 MB.
            $logGrowthBeforeReduce = $tempdbReductionServer.Databases["tempdb"].Query("SELECT growth AS GrowthValue FROM sys.database_files WHERE type = 1").GrowthValue

            # Run the reduction through the connection that starts in msdb, so that the assertion below can
            # show that the command leaves the database of the caller where it found it. This is the path
            # that moves it twice: reading tempdb through FILEPROPERTY, which only reports on the current
            # database, and then the batches, which carry an explicit USE [tempdb] because DBCC SHRINKFILE
            # empties a file of the current database only.
            $splatReduce = @{
                SqlInstance     = $tempdbContextServer
                DataFileCount   = $originalDataFileCount
                DataFileSize    = $expandedTotalDataFileSize
                DataPath        = $tempdbReductionDataPath
                Force           = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                EnableException = $true
            }
            $reduceResult = Set-DbaTempDbConfig @splatReduce
            $reduceResult.DataFileCount | Should -Be $originalDataFileCount

            $logGrowthAfterReduce = $tempdbReductionServer.Databases["tempdb"].Query("SELECT growth AS GrowthValue FROM sys.database_files WHERE type = 1").GrowthValue
            $logGrowthAfterReduce | Should -Be $logGrowthBeforeReduce

            $tempdbContextServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "msdb"

            $reducedFiles = @(Get-DbaDbFile -SqlInstance $tempdbReductionServer -Database tempdb | Where-Object Type -eq 0)
            $reducedFiles.Count | Should -Be $originalDataFileCount
            $reducedFiles.ID | Should -Contain 1
            foreach ($removedFile in $expectedRemovedFiles) {
                $reducedFiles.LogicalName | Should -Not -Contain $removedFile.LogicalName
            }

            $preservedRowCount = $tempdbReductionServer.Databases["tempdb"].Query("SELECT COUNT(1) AS PreservedRows FROM dbo.[$allocationTableName]").PreservedRows
            $preservedRowCount | Should -Be $allocationRowCount
            $tempdbReductionServer.Databases["tempdb"].ExecuteNonQuery("DROP TABLE dbo.[$allocationTableName];")
        }
    }
}
