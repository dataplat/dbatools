#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileMapping",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "returns information about multiple databases" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $true
        }
    }

    Context "Should return file information for a single database" {
        It "returns information about tempdb" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $false
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
            $sourceDbName = "dbatoolsci_mapping_source_$(Get-Random)"
            $restoringDbName = "dbatoolsci_mapping_restoring_$(Get-Random)"

            # This is the scenario from the issue: the mapping of a database left in NORECOVERY by a
            # full restore is what the differential restore that follows it needs.
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

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $restoringMapping = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database $restoringDbName

            # Bringing the database online lets the mapping taken while it was inaccessible be compared
            # against the one SMO builds for the very same files.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Recover -DatabaseName $restoringDbName
            $recoveredMapping = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database $restoringDbName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects.
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $sourceDbName, $restoringDbName -ErrorAction SilentlyContinue

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns a mapping for a database that is still in NORECOVERY" {
            $restoringMapping | Should -Not -BeNullOrEmpty
            $restoringMapping.Database | Should -Be $restoringDbName
            $restoringMapping.FileMapping.Count | Should -BeExactly 2
        }

        It "Maps the logical names of the source database to the physical names the restore created" {
            $dataFile = $restoringMapping.FileMapping[$sourceDbName]
            $logFile = $restoringMapping.FileMapping["${sourceDbName}_log"]
            $dataFile | Should -BeLike "*$restoringDbName*.mdf"
            $logFile | Should -BeLike "*$restoringDbName*.ldf"
        }

        It "Builds the same mapping while inaccessible as it does once the database is recovered" {
            $restoringPairs = ($restoringMapping.FileMapping.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($PSItem.Name)=$($PSItem.Value)" }) -join ";"
            $recoveredPairs = ($recoveredMapping.FileMapping.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($PSItem.Name)=$($PSItem.Value)" }) -join ";"
            $restoringPairs | Should -Be $recoveredPairs
        }
    }
}