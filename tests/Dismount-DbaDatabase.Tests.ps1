$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"




Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	# Setting up the environment we need to test the cmdlet
	BeforeAll {
		# Everything in here gets executed before anything else in this context
		
		# Setting up variables names. If you want them to persist between all of the pester blocks, they can be moved outside
		$dbname = "dbatoolsci_detachattach"
		# making room in the remote case a db with the same name exists
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase
		# restoring from the "common test data" (see https://github.com/sqlcollaborative/appveyor-lab)
		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path C:\github\appveyor-lab\detachattach\detachattach.bak -DatabaseName $dbname -WithReplace
		
		# memorizing $fileStructure for a later test
		$fileStructure = New-Object System.Collections.Specialized.StringCollection
	
		foreach ($file in (Get-DbaDatabaseFile -SqlInstance $script:instance1 -Database $dbname).PhysicalName) {
			$null = $fileStructure.Add($file)
		}
	}
	
	# Everything we create/touch/mess with should be reverted to a "clean" state whenever possible
	AfterAll {
		# this gets executed always (think "finally" in try/catch/finally) and it's the best place for final cleanups
		$null = Attach-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -FileStructure $script:fileStructure
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $script:dbname | Remove-DbaDatabase
	}
	
	# Actual tests
	Context "Detaches a single database and tests to ensure the alias still exists" {
		$results = Detach-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Force
		
		It "was successfull" {
			$results.DetachResult | Should Be "Success"
		}
		
		It "removed just one database" {
			$results.Database | Should Be $dbname
		}
		
		It "has the correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,DetachResult'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}
	}
	

}