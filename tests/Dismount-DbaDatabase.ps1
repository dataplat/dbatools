Describe "Dismount-DbaDatabase Integration Tests" -Tags "Integrationtests" {

    Context "Setup removes, restores and backups on the local drive for Dismount-DbaDatabase" {
        $null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        $null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
    }
	
    Context "Detaches a single database and tests to ensure the alias still exists" {
        $results = Detach-DbaDatabase -SqlInstance localhost -Database singlerestore
		
        It "Should return success" {
            $results.DetachResult | Should Be "Success"
        }
		
		It "Should return that the database is only Database" {
            $results.Database | Should Be "singlerestore"
        }
    }
}