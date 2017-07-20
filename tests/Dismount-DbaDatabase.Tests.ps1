Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Dismount-DbaDatabase Integration Tests" -Tags "IntegrationTests" {
	$dbname = "detachattach"
	$null = Get-DbaDatabase -SqlInstance localhost -Database $dbname | Remove-DbaDatabase
	
	Context "Setup removes, restores and backups and preps reattach" {
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\detachattach\detachattach.bak -WithReplace
		
		$script:fileStructure = New-Object System.Collections.Specialized.StringCollection
		
		foreach ($file in (Get-DbaDatabaseFile -SqlInstance localhost -Database $dbname).PhysicalName) {
			$null = $script:fileStructure.Add($file)
		}
	}
	
	Context "Detaches a single database and tests to ensure the alias still exists" {
		$results = Detach-DbaDatabase -SqlInstance localhost -Database $dbname -Force
		
		It "Should return success" {
			$results.DetachResult | Should Be "Success"
		}
		
		It "Should return that the database is only Database" {
			$results.Database | Should Be $dbname
		}
	}
	
	Context "Reattaches and deletes" {
		$null = Attach-DbaDatabase -SqlInstance localhost -Database $dbname -FileStructure $script:fileStructure
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
	}
}