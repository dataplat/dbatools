$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Orphaned files are correctly identified" {
		BeforeAll {
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			$dbname = "dbatoolsci_findme"
			Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase
			$server.Query("CREATE DATABASE $dbname")
		}
		AfterAll {
			Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase
		}
		$null = Detach-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Force
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1
		
		It "Has the correct default properties" {
			$ExpectedStdProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename'.Split(',')
			($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedStdProps | Sort-Object)
		}
		It "Has the correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server'.Split(',')
			($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}
		
		It "Finds two files" {
			$results.Count | Should Be 2
		}
		
		$results.FileName | Remove-Item
		
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1
		It "Finds zero files after cleaning up" {
			$results.Count | Should Be 0
		}
		
	}
}
