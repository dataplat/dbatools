Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Mount-DbaDatabase Integration Tests" -Tags "Integrationtests" {

    Context "Setup removes, restores and backups on the local drive for Mount-DbaDatabase" {
        $null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        $null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\detachattach\detachattach.bak -WithReplace
		$null = Get-DbaDatabase -SqlInstance localhost -Database detachattach | Backup-DbaDatabase -Type Full
		$null = Get-DbaDatabase -SqlInstance localhost -Database detachattach | Backup-DbaDatabase -Type Differential
		$null = Get-DbaDatabase -SqlInstance localhost -Database detachattach | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance localhost -Database detachattach | Backup-DbaDatabase -Type Full
		$null = Detach-DbaDatabase -SqlInstance localhost -Database detachattach -Force
    }
	
    Context "Attaches a single database and tests to ensure the alias still exists" {
        $results = Attach-DbaDatabase -SqlInstance localhost -Database detachattach
		
        It "Should return success" {
            $results.AttachResult | Should Be "Success"
        }
		
		It "Should return that the database is only Database" {
            $results.Database | Should Be "detachattach"
        }
		
		It "Should return that the AttachOption default is None" {
            $results.AttachOption | Should Be "None"
        }
	}
	
	$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
}