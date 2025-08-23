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
}
Describe $CommandName -Tag IntegrationTests {
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