#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFile",
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
                "FileGroup",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Ensure array" {
        It "Returns disks as an array" {
            $results = Get-Command -Name Get-DbaDbFile | Select-Object -ExpandProperty ScriptBlock
            $results -match '\$disks \= \@\(' | Should -Be $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "Returns information about tempdb files" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle
            $results.Database -contains "tempdb" | Should -Be $true
        }
    }

    Context "Should return file information for only tempdb" {
        It "Returns only tempdb files" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            foreach ($result in $results) {
                $result.Database | Should -Be "tempdb"
            }
        }
    }

    Context "Should return file information for only tempdb primary filegroup" {
        It "Returns only tempdb files that are in Primary filegroup" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database tempdb -FileGroup Primary
            foreach ($result in $results) {
                $result.Database | Should -Be "tempdb"
                $result.FileGroupName | Should -Be "Primary"
            }
        }
    }

    Context "Physical name is populated" {
        It "Master returns proper results" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database master
            $result = $results | Where-Object LogicalName -eq "master"
            $result.PhysicalName -match "master.mdf" | Should -Be $true
            $result = $results | Where-Object LogicalName -eq "mastlog"
            $result.PhysicalName -match "mastlog.ldf" | Should -Be $true
        }
    }

    Context "Database ID is populated" {
        It "Returns proper results for the master db" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database master
            $results.DatabaseID | Get-Unique | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master).ID
        }

        It "Uses a pipeline input and returns proper results for the tempdb" {
            $tempDB = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $results = $tempDB | Get-DbaDbFile
            $results.DatabaseID | Get-Unique | Should -Be $tempDB.ID
        }
    }

    Context "Database names that contain an apostrophe" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Set variables. They are available in all the It blocks.
            $quotedDbName = "dbatoolsci_dbfile_$([char]39)quoted_$(Get-Random)"

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $quotedDbName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $quotedResults = @(Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $quotedDbName)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects.
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $quotedDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the files of a database whose name contains an apostrophe" {
            $quotedResults.Count | Should -BeExactly 2
            $quotedResults.Database | Select-Object -Unique | Should -Be $quotedDbName
        }

        It "Detects the compatibility level instead of falling back to the SQL Server 2000 query" {
            # The version probe used to interpolate the database name into a string comparison, so an
            # apostrophe made it throw and the command silently served the SQL 2000 shape, which has no
            # NumberOfDiskReads column.
            $null -ne $quotedResults[0].NumberOfDiskReads | Should -BeTrue
        }
    }

    Context "Databases that cannot be opened" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            # Set variables. They are available in all the It blocks.
            $sourceDbName = "dbatoolsci_dbfile_source_$(Get-Random)"
            $restoringDbName = "dbatoolsci_dbfile_restoring_$(Get-Random)"
            $offlineDbName = "dbatoolsci_dbfile_offline_$(Get-Random)"

            # The offline database is compared against itself while it is still online, so the fallback
            # has to reproduce the values the normal query returns rather than just return something.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDbName
            $onlineResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Offline -Force

            # The restoring database is the scenario from the issue: a full restore left in NORECOVERY
            # so that a differential can follow it.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $sourceDbName
            $fullBackup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $sourceDbName -Path $backupPath -Type Full

            $splatRestore = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Path                = $fullBackup.BackupPath
                DatabaseName        = $restoringDbName
                NoRecovery          = $true
                ReplaceDbNameInFile = $true
            }
            $null = Restore-DbaDatabase @splatRestore

            $accessibleResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $sourceDbName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $restoringResults = @(Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $restoringDbName)
            $offlineResults = @(Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects.
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Online -Force -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $sourceDbName, $restoringDbName, $offlineDbName -ErrorAction SilentlyContinue

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the files of a database that is still in NORECOVERY" {
            $restoringResults.Count | Should -BeExactly 2
            $restoringResults.State | Select-Object -Unique | Should -Be "RESTORING"
        }

        It "Reports the physical names the restore created for the database in NORECOVERY" {
            $dataFile = $restoringResults | Where-Object TypeDescription -eq "ROWS"
            $logFile = $restoringResults | Where-Object TypeDescription -eq "LOG"
            $dataFile.PhysicalName | Should -BeLike "*$restoringDbName*.mdf"
            $logFile.PhysicalName | Should -BeLike "*$restoringDbName*.ldf"
        }

        It "Keeps the logical names of the source database for the database in NORECOVERY" {
            $restoringResults.LogicalName | Sort-Object | Should -Be ($accessibleResults.LogicalName | Sort-Object)
        }

        It "Returns the files of an offline database" {
            $offlineResults.Count | Should -BeExactly 2
        }

        It "Reports the same file layout for the offline database as it did while it was online" {
            $properties = @(
                "ID",
                "Type",
                "TypeDescription",
                "LogicalName",
                "PhysicalName",
                "MaxSize",
                "Growth",
                "GrowthType",
                "Size",
                "IsReadOnly",
                "IsSparse",
                "FileGroupDataSpaceId"
            )
            $offline = $offlineResults | Sort-Object ID | Select-Object $properties
            $online = @($onlineResults) | Sort-Object ID | Select-Object $properties
            Compare-Object -ReferenceObject $online -DifferenceObject $offline -Property $properties | Should -BeNullOrEmpty
        }

        It "Returns the same properties in the same order as for an accessible database" {
            $inaccessibleProperties = $restoringResults[0].PSObject.Properties.Name -join ","
            $inaccessibleProperties | Should -Be ($accessibleResults[0].PSObject.Properties.Name -join ",")
        }

        It "Reports what it cannot read as null instead of zero" {
            $file = $restoringResults[0]
            # Without this the whole test passes trivially when no file is returned at all.
            $file.LogicalName | Should -Not -BeNullOrEmpty
            $file.UsedSpace | Should -BeNullOrEmpty
            $file.AvailableSpace | Should -BeNullOrEmpty
            $file.NumberOfDiskWrites | Should -BeNullOrEmpty
            $file.NumberOfDiskReads | Should -BeNullOrEmpty
            $file.ReadFromDisk | Should -BeNullOrEmpty
            $file.WrittenToDisk | Should -BeNullOrEmpty
            $file.VolumeFreeSpace | Should -BeNullOrEmpty
            $file.FileGroupName | Should -BeNullOrEmpty
            $file.FileGroupType | Should -BeNullOrEmpty
            $file.FileGroupTypeDescription | Should -BeNullOrEmpty
            $file.FileGroupDefault | Should -BeNullOrEmpty
            $file.FileGroupReadOnly | Should -BeNullOrEmpty
        }

        It "Does not warn about a database that cannot be opened" {
            $null = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $restoringDbName -WarningVariable restoringWarning
            $restoringWarning | Should -BeNullOrEmpty
        }

        It "Warns and returns nothing when FileGroup is used on a database that cannot be opened" {
            $filteredResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $restoringDbName -FileGroup PRIMARY -WarningVariable fileGroupWarning
            $filteredResults | Should -BeNullOrEmpty
            $fileGroupWarning | Should -Match "FileGroup cannot be honored"
        }

        It "Still returns the accessible databases when scanning the whole instance" {
            $allResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle
            $allResults.Database | Should -Contain $sourceDbName
            $allResults.Database | Should -Contain $restoringDbName
            $allResults.Database | Should -Contain $offlineDbName
        }
    }
}