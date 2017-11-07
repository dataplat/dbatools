$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Recovery model is correctly identified" {
		$results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2 -Database master
		
		It "returns a single database" {
			$results.Count | Should Be 1
		}
		
		It "returns a the correct recovery model" {
			$results.RecoveryModel -eq 'Simple' | Should Be $true
		}
		
		$results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2
		
		It "returns accurate number of results" {
			$results.Count -ge 4 | Should Be $true
		}
	}
}