$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
	InModuleScope dbatools {
		Context "General Diff restore" {
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
			Mock Read-DbaBackupHeader { $Header }
			$RawFilteredFiles = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
			$FilteredFiles = $RawFilteredFiles[0].values
			It "Should Return 7" {
				$FilteredFiles.count | should be 7
			}
			It "Should return True" {
				$Output = Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles -WarningAction SilentlyContinue
				$Output | Should be True
			}
			$Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
			Mock Read-DbaBackupHeader { $Header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' } }
			$RawFilteredFiles = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
			$FilteredFiles = $RawFilteredFiles[0].values
			It "Should return true if we remove diff backup" {
				$Output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles ($FilteredFiles | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' })
				$Output | Should be True
			}
			
			It "Should return False (faked lsn)" {
				$FilteredFiles[4].FirstLsn = 2
				$FilteredFiles[4].LastLsn = 1
				$Output = $FilteredFiles | Test-DbaLsnChain -WarningAction SilentlyContinue
				$Output | Should be $False
			}
		}
	}
}