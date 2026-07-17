#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Select-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "BackupHistory",
                "RestoreTime",
                "IgnoreLogs",
                "IgnoreDiffs",
                "DatabaseName",
                "ServerName",
                "ContinuePoints",
                "LastRestoreType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Copy-only full point-in-time restore chains" {
            BeforeAll {
                function New-CopyOnlyBackupHistory {
                    @(
                        [PSCustomObject]@{
                            Database                  = "CopyOnlyRestore"
                            Type                      = "Database"
                            BackupTypeDescription     = "Database"
                            BackupSetID               = 1
                            Start                     = Get-Date "2025-01-01 00:00:00"
                            End                       = Get-Date "2025-01-01 00:10:00"
                            FirstLSN                  = [bigint]50
                            LastLSN                   = [bigint]200
                            CheckpointLSN             = [bigint]100
                            DatabaseBackupLSN         = [bigint]100
                            FirstRecoveryForkID       = "fork-a"
                            IsCopyOnly                = $false
                            FullName                  = "C:\backups\conventional-full.bak"
                        }
                        [PSCustomObject]@{
                            Database                  = "CopyOnlyRestore"
                            Type                      = "Database"
                            BackupTypeDescription     = "Database"
                            BackupSetID               = 2
                            Start                     = Get-Date "2025-01-01 01:00:00"
                            End                       = Get-Date "2025-01-01 01:10:00"
                            FirstLSN                  = [bigint]250
                            LastLSN                   = [bigint]400
                            CheckpointLSN             = [bigint]300
                            DatabaseBackupLSN         = [bigint]100
                            FirstRecoveryForkID       = "fork-a"
                            IsCopyOnly                = $true
                            FullName                  = "C:\backups\copy-only-full.bak"
                        }
                        [PSCustomObject]@{
                            Database                  = "CopyOnlyRestore"
                            Type                      = "Transaction Log"
                            BackupTypeDescription     = "Transaction Log"
                            BackupSetID               = 5
                            Start                     = Get-Date "2025-01-01 01:45:00"
                            End                       = Get-Date "2025-01-01 01:50:00"
                            FirstLSN                  = [bigint]350
                            LastLSN                   = [bigint]425
                            CheckpointLSN             = [bigint]0
                            DatabaseBackupLSN         = [bigint]100
                            FirstRecoveryForkID       = "fork-b"
                            IsCopyOnly                = $false
                            FullName                  = "C:\backups\wrong-fork-log.trn"
                        }
                        [PSCustomObject]@{
                            Database                  = "CopyOnlyRestore"
                            Type                      = "Transaction Log"
                            BackupTypeDescription     = "Transaction Log"
                            BackupSetID               = 3
                            Start                     = Get-Date "2025-01-01 02:00:00"
                            End                       = Get-Date "2025-01-01 02:05:00"
                            FirstLSN                  = [bigint]350
                            LastLSN                   = [bigint]450
                            CheckpointLSN             = [bigint]0
                            DatabaseBackupLSN         = [bigint]100
                            FirstRecoveryForkID       = "fork-a"
                            IsCopyOnly                = $false
                            FullName                  = "C:\backups\log-1.trn"
                        }
                        [PSCustomObject]@{
                            Database                  = "CopyOnlyRestore"
                            Type                      = "Transaction Log"
                            BackupTypeDescription     = "Transaction Log"
                            BackupSetID               = 4
                            Start                     = Get-Date "2025-01-01 03:00:00"
                            End                       = Get-Date "2025-01-01 03:05:00"
                            FirstLSN                  = [bigint]451
                            LastLSN                   = [bigint]550
                            CheckpointLSN             = [bigint]0
                            DatabaseBackupLSN         = [bigint]100
                            FirstRecoveryForkID       = "fork-a"
                            IsCopyOnly                = $false
                            FullName                  = "C:\backups\log-2.trn"
                        }
                    )
                }
            }

            It "selects terminal log 3 once when the restore time is before the first log starts" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -RestoreTime (Get-Date "2025-01-01 01:30:00") -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                @($selectedLogIDs | Where-Object { $PSItem -eq 3 }).Count | Should -Be 1
                $selectedLogIDs | Should -Not -Contain 5
            }

            It "selects terminal log 3 once when the restore time equals the log start" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -RestoreTime (Get-Date "2025-01-01 02:00:00") -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                @($selectedLogIDs | Where-Object { $PSItem -eq 3 }).Count | Should -Be 1
                $selectedLogIDs | Should -Not -Contain 5
            }

            It "selects terminal log 3 once when the restore time is inside the log" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -RestoreTime (Get-Date "2025-01-01 02:02:00") -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                @($selectedLogIDs | Where-Object { $PSItem -eq 3 }).Count | Should -Be 1
                $selectedLogIDs | Should -Not -Contain 5
            }

            It "selects terminal log 3 once when the restore time equals the log end" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -RestoreTime (Get-Date "2025-01-01 02:05:00") -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                @($selectedLogIDs | Where-Object { $PSItem -eq 3 }).Count | Should -Be 1
                $selectedLogIDs | Should -Not -Contain 5
            }

            It "selects terminal log 4 once when the restore time falls between logs" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -RestoreTime (Get-Date "2025-01-01 02:30:00") -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                @($selectedLogIDs | Where-Object { $PSItem -eq 3 }).Count | Should -Be 1
                @($selectedLogIDs | Where-Object { $PSItem -eq 4 }).Count | Should -Be 1
                $selectedLogIDs | Should -Not -Contain 5
            }

            It "selects each applicable log once when RestoreTime is not specified" {
                $output = @(New-CopyOnlyBackupHistory | Select-DbaBackupInformation -EnableException)
                $selectedLogIDs = @($output | Where-Object Type -eq "Transaction Log" | ForEach-Object BackupSetID)

                $output[0].BackupSetID | Should -Be 2
                $selectedLogIDs | Should -Be @(3, 4)
                @($selectedLogIDs | Select-Object -Unique).Count | Should -Be $selectedLogIDs.Count
            }
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    InModuleScope dbatools {
        Context "General Diff Restore" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1
                $Output = Select-DbaBackupInformation -BackupHistory $header -EnableException:$true
            }

            It "Should return an array of 7 items" {
                $Output.count | Should -Be 7
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 5 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 5
            }
        }

        Context "AG  Diff Restore" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\AGDiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1
                $Output = Select-DbaBackupInformation -BackupHistory $header -EnableException:$true
            }

            It "Should return an array of 7 items" {
                $Output.count | Should -Be 7
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 5 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 5
            }
            It "Should return 7 objects from AG1" {
                ($Output | Where-Object AvailabilityGroupName -eq "AG1" | Measure-Object).count | Should -Be 7
            }
            It "Should return 2 objects from Server 1" {
                ($Output | Where-Object ServerName -eq "Server1" | Measure-Object).count | Should -Be 2
            }
            It "Should return 5 objects from Server 2" {
                ($Output | Where-Object ServerName -eq "Server2" | Measure-Object).count | Should -Be 5
            }
        }

        Context "General Diff Restore from Pipeline" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1
                $Output = $Header | Select-DbaBackupInformation -EnableException:$true
            }

            It "Should return an array of 7 items" {
                $Output.count | Should -Be 7
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 5 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 5
            }
        }
        Context "General Diff Restore from Pipeline with IgnoreDiff" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1
                $Output = $Header | Select-DbaBackupInformation -EnableException:$true -IgnoreDiff
            }

            It "Should return an array of 9 items" {
                $Output.count | Should -Be 9
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 0 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 0
            }
            It "Should return 8 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 8
            }
        }
        Context "General Diff Restore from Pipeline with IgnoreLog" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1
                $Output = $Header | Select-DbaBackupInformation -EnableException:$true -IgnoreLogs
            }

            It "Should return an array of 2 items" {
                $Output.count | Should -Be 2
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 0 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 0
            }
        }
        Context "Server/database names and file paths have commas and spaces" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreCommaIssues.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value "test"

                $Output = Select-DbaBackupInformation -BackupHistory $header
            }

            It "Should return an array of 7 items" {
                $Output.count | Should -Be 7
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 5 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 5
            }
        }
        Context "Missing Diff Restore" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header = $header | Where-Object BackupTypeDescription -ne "Database Differential"
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                $Output = Select-DbaBackupInformation -BackupHistory $header
            }

            It "Should return an array of 9 items" {
                $Output.count | Should -Be 9
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 0 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 0
            }
            It "Should return 8 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 8
            }
        }
        Context "Overlapping Diff and log Restore" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffIssues.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                $RestoreDate = Get-Date "2017-07-18 09:00:00"
                $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
            }

            It "Should return an array of 193 items" {
                $Output.count | Should -Be 194
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 192 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 192
            }
            It "Should not contain the Log backup with LastLsn 17126786000011867500001 " {
                ($Output | Where-Object LastLsn -eq "17126786000011867500001" | Measure-Object).count | Should -Be 0
            }
        }
        Context "When FirstLSN ne CheckPointLsn" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\chkptLSN-ne-firstLSN.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                $RestoreDate = Get-Date "2017-07-18 09:00:00"
                $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
            }

            It "Should return an array of 193 items" {
                $Output.count | Should -Be 194
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 1 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 1
            }
            It "Should return 192 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 192
            }
            It "Should not contain the Log backup with LastLsn 17126786000011867500001 " {
                ($Output | Where-Object LastLsn -eq "17126786000011867500001" | Measure-Object).count | Should -Be 0
            }
        }
        Context "When TLogs between full's FirstLsn and LastLsn" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\TLogBWFirstLastLsn.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                $RestoreDate = Get-Date "2017-07-18 09:00:00"
                $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
            }

            It "Should return an array of 3 items" {
                $Output.count | Should -Be 3
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 0 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 0
            }
            It "Should return 2 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 2
            }
            It "Should not contain the Log backup with LastLsn 14975000000265600001 " {
                ($Output | Where-Object LastLsn -eq "14975000000265600001" | Measure-Object).count | Should -Be 0
            }
        }
        Context "Last log backup has same lastlsn as consequent backups" {
            BeforeAll {
                $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\broken_chain.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                $RestoreDate = Get-Date "2017-07-16 17:51:30"
                $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
            }

            It "Should return an array of 3 items" {
                $Output.count | Should -Be 3
            }
            It "Should return 1 Full backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database" | Measure-Object).count | Should -Be 1
            }
            It "Should return 0 Diff backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Database Differential" | Measure-Object).count | Should -Be 0
            }
            It "Should return 2 log backups" {
                ($Output | Where-Object BackupTypeDescription -eq "Transaction Log" | Measure-Object).count | Should -Be 2
            }
            It "Should not contain the Log backup with FirstLsn=LastLsn=17126658000000315600037 " {
                ($Output | Where-Object { $PSItem.LastLsn -eq "17126658000000315600037" -and $PSItem.FirstLsn -eq "17126658000000315600037" } | Measure-Object).count | Should -Be 0
            }
            It "Should contain the Log backup with FirstLsn 17126658000000314600037 " {
                ($Output | Where-Object FirstLsn -eq "17126658000000314600037" | Measure-Object).count | Should -Be 1
            }
        }
        Context "Continue Points" {
            BeforeAll {
                $BackupInfo = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
                [bigint]$redo_start_lsn = "34000000016700004"
                $ContinuePoints = [PSCustomObject]@{
                    redo_start_lsn      = $redo_start_lsn
                    FirstRecoveryForkID = "00000000-0000-0000-0000-000000000000"
                    Database            = "ContinuePointTest"
                }
                $Output = Select-DbaBackupInformation -BackupHistory $BackupInfo -EnableException:$true -ContinuePoints $ContinuePoints
            }

            It "Should return an array of 4 items" {
                $Output.count | Should -Be 4
            }
            It "Should return 0 Full backups" {
                ($Output | Where-Object Type -eq "Database" | Measure-Object).count | Should -Be 0
            }
            It "Should return 0 Diff backups" {
                ($Output | Where-Object Type -eq "Database Differential" | Measure-Object).count | Should -Be 0
            }
            It "Should return 4 log backups" {
                ($Output | Where-Object Type -eq "Transaction Log" | Measure-Object).count | Should -Be 4
            }
            It "Should start with a log backup including redo_start_lsn" {
                $tmp = ($output | Sort-Object -Property FirstLSn)[0]
                ($redo_start_lsn -ge $tmp.FirstLsn -and $redo_start_lsn -le $tmp.LastLsn) | Should -Be $true
            }
        }

    }
}
