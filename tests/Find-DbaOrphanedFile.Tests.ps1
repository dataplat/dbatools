$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Orphaned files are correctly identified" {
		BeforeAll {
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			$dbname = "dbatoolsci_findme"
			$server.Query("CREATE DATABASE $dbname")
		}
		$null = Detach-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Force
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1
		It "Finds two files" {
			$results.Count | Should Be 2
		}
		It "Has the correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}
		
		$results.FileName | Remove-Item
		
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1
		It "Finds zero files after cleaning up" {
			$results.Count | Should Be 0
		}
		
	}
}
