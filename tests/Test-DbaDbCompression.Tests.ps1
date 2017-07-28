$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Properly restores a database on the local drive using Path" {
		$null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
		$results = Test-DbaDbCompression -SqlInstance $script:instance2 -Database singlerestore
		It "Should Return the proper backup file location" {
			#$results.BackupFile | Should Be "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
		}
		It "Should return successful restore" {
			#$results.RestoreComplete | Should Be $true
		}
		$null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database singlerestore
	}
}
#>