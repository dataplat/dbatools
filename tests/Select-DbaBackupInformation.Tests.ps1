param($ModuleName = 'dbatools')

Describe "Select-DbaBackupInformation" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Select-DbaBackupInformation
        }
        It "Should have BackupHistory as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter BackupHistory
        }
        It "Should have RestoreTime as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreTime
        }
        It "Should have IgnoreLogs as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreLogs
        }
        It "Should have IgnoreDiffs as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreDiffs
        }
        It "Should have DatabaseName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseName
        }
        It "Should have ServerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ServerName
        }
        It "Should have ContinuePoints as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ContinuePoints
        }
        It "Should have LastRestoreType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LastRestoreType
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "General Diff Restore" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $Output = Select-DbaBackupInformation -BackupHistory $header -EnableException:$true
        }

        It "Should return an array of 7 items" {
            $Output.count | Should -Be 7
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 5 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 5
        }
    }

    Context "AG Diff Restore" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\AGDiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $Output = Select-DbaBackupInformation -BackupHistory $header -EnableException:$true
        }

        It "Should return an array of 7 items" {
            $Output.count | Should -Be 7
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 5 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 5
        }
        It "Should return 7 objects from AG1" {
            ($Output | Where-Object { $_.AvailabilityGroupName -eq 'AG1' }).count | Should -Be 7
        }
        It "Should return 2 objects from Server 1" {
            ($Output | Where-Object { $_.ServerName -eq 'Server1' }).count | Should -Be 2
        }
        It "Should return 5 objects from Server 2" {
            ($Output | Where-Object { $_.ServerName -eq 'Server2' }).count | Should -Be 5
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
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 5 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 5
        }
    }

    Context "General Diff Restore from Pipeline with IgnoreDiff" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $Output = $Header | Select-DbaBackupInformation -EnableException:$true -IgnoreDiffs
        }

        It "Should return an array of 9 items" {
            $Output.count | Should -Be 9
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 0
        }
        It "Should return 8 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 8
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
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 0 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 0
        }
    }

    Context "Server/database names and file paths have commas and spaces" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreCommaIssues.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 'test'
            $Output = Select-DbaBackupInformation -BackupHistory $header
        }

        It "Should return an array of 7 items" {
            $Output.count | Should -Be 7
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 5 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 5
        }
    }

    Context "Missing Diff Restore" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header = $header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' }
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $Output = Select-DbaBackupInformation -BackupHistory $header
        }

        It "Should return an array of 9 items" {
            $Output.count | Should -Be 9
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 0
        }
        It "Should return 8 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 8
        }
    }

    Context "Overlapping Diff and log Restore" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffIssues.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $RestoreDate = Get-date "2017-07-18 09:00:00"
            $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
        }

        It "Should return an array of 194 items" {
            $Output.count | Should -Be 194
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 192 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 192
        }
        It "Should not contain the Log backup with LastLsn 17126786000011867500001" {
            ($Output | Where-Object { $_.LastLsn -eq '17126786000011867500001' }).count | Should -Be 0
        }
    }

    Context "When FirstLSN ne CheckPointLsn" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\chkptLSN-ne-firstLSN.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $RestoreDate = Get-date "2017-07-18 09:00:00"
            $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
        }

        It "Should return an array of 194 items" {
            $Output.count | Should -Be 194
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 1 Diff backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 1
        }
        It "Should return 192 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 192
        }
        It "Should not contain the Log backup with LastLsn 17126786000011867500001" {
            ($Output | Where-Object { $_.LastLsn -eq '17126786000011867500001' }).count | Should -Be 0
        }
    }

    Context "When TLogs between full's FirstLsn and LastLsn" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\TLogBWFirstLastLsn.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $RestoreDate = Get-date "2017-07-18 09:00:00"
            $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
        }

        It "Should return an array of 3 items" {
            $Output.count | Should -Be 3
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 0
        }
        It "Should return 2 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 2
        }
        It "Should not contain the Log backup with LastLsn 14975000000265600001" {
            ($Output | Where-Object { $_.LastLsn -eq '14975000000265600001' }).count | Should -Be 0
        }
    }

    Context "Last log backup has same lastlsn as consequent backups" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\broken_chain.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1
            $RestoreDate = Get-date "2017-07-16 17:51:30"
            $Output = Select-DbaBackupInformation -BackupHistory $Header -RestoreTime $RestoreDate
        }

        It "Should return an array of 3 items" {
            $Output.count | Should -Be 3
        }
        It "Should return 1 Full backup" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database' }).count | Should -Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' }).count | Should -Be 0
        }
        It "Should return 2 log backups" {
            ($Output | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' }).count | Should -Be 2
        }
        It "Should not contain the Log backup with FirstLsn=LastLsn=17126658000000315600037" {
            ($Output | Where-Object { $_.LastLsn -eq '17126658000000315600037' -and $_.FirstLsn -eq '17126658000000315600037' }).count | Should -Be 0
        }
        It "Should contain the Log backup with FirstLsn 17126658000000314600037" {
            ($Output | Where-Object { $_.FirstLsn -eq '17126658000000314600037' }).count | Should -Be 1
        }
    }

    Context "Continue Points" {
        BeforeAll {
            $BackupInfo = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            [bigint]$redo_start_lsn = '34000000016700004'
            $ContinuePoints = [PsCustomObject]@{
                redo_start_lsn      = $redo_start_lsn
                FirstRecoveryForkID = '00000000-0000-0000-0000-000000000000'
                Database            = 'ContinuePointTest'
            }
            $Output = Select-DbaBackupInformation -BackupHistory $BackupInfo -EnableException:$true -ContinuePoints $ContinuePoints
        }

        It "Should return an array of 4 items" {
            $Output.count | Should -Be 4
        }
        It "Should return 0 Full backups" {
            ($Output | Where-Object { $_.Type -eq 'Database' }).count | Should -Be 0
        }
        It "Should return 0 Diff backups" {
            ($Output | Where-Object { $_.Type -eq 'Database Differential' }).count | Should -Be 0
        }
        It "Should return 4 log backups" {
            ($Output | Where-Object { $_.Type -eq 'Transaction Log' }).count | Should -Be 4
        }
        It "Should start with a log backup including redo_start_lsn" {
            $tmp = ($output | Sort-Object -Property FirstLSn)[0]
            ($redo_start_lsn -ge $tmp.FirstLsn -and $redo_start_lsn -le $tmp.LastLsn) | Should -BeTrue
        }
    }
}
