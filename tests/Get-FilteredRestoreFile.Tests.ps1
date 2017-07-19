Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Get-FilteredRestoreFile Unit Tests" -Tag 'Unittests' {
	InModuleScope dbatools {
		Context "Empty TLog Backup Issues" {
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\EmptyTlogData.json -raw)
			Mock Read-DbaBackupHeader { $Header }
			$Output = Get-FilteredRestoreFile -SqlServer TestSQL -Files "c:\dummy.txt" -silent:$true
			
			It "Should return an array of 3 items" {
				$Output[0].values.count | Should be 3
			}
			It "Should return 1 Full backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
			}
			It "Should return 0 Diff backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 0
			}
			It "Should return 2 log backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 2
			}
		}
		Context "General Diff Restore" {
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
			Mock Read-DbaBackupHeader { $Header }
			$Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
			
			It "Should return an array of 7 items" {
				$Output[0].values.count | Should be 7
			}
			It "Should return 1 Full backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
			}
			It "Should return 1 Diff backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 1
			}
			It "Should return 5 log backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 5
			}
		}
		Context "Missing Diff Restore" {
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
			$header = $header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' }
			Mock Read-DbaBackupHeader { $Header }
			$Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
			$Output
			It "Should return an array of 9 items" {
				$Output[0].values.count | Should be 9
			}
			It "Should return 1 Full backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
			}
			It "Should return 0 Diff backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 0
			}
			It "Should return 8 log backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 8
			}
		}
		Context "Overlapping Diff and log Restore" {
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffIssues.json -raw)
			Mock Read-DbaBackupHeader { $Header }
			$RestoreDate =  Get-date "2017-07-18 09:00:00"
			$Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt" -RestoreTime $RestoreDate
			$Output
			It "Should return an array of 193 items" {
				$Output[0].values.count | Should be 194
			}
			It "Should return 1 Full backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
			}
			It "Should return 1 Diff backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 1
			}
			It "Should return 191 log backups" {
				($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 192
			}
			It "Should not contain the Log backup with LastLsn 17126786000011867500001 " {
				($Output[0].values | Where-Object { $_.LastLsn -eq '17126786000011867500001' } | Measure-Object).count | Should Be 0
			}
		}
	}
}