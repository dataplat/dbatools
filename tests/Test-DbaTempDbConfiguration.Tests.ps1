. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if tempdb misconfiguration is reported" {
		$results = Test-DbaTempDbConfiguration -SqlInstance $script:instance1
		
		It "reports back issue for files on C drive" {
			$results.Rule -match 'File Location' | Should Be $true
		}
	}
}