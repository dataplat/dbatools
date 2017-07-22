$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

	Context "Count system databases on localhost" {
		$results = Get-DbaDatabase -SqlInstance $script:instance1 -NoUserDb 
		It "Should report the right number of databases" {
			$results.Count | Should Be 4
		}
	}

	Context "Check that master database is in Simple recovery mode" {
		$results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master
		It "Should say the recovery mode of master is Simple" {
			$results.RecoveryModel | Should Be "Simple"
		}
	}
	
	Context "Check that master database is accessible" {
		$results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master
		It "Should return true that master is accessible" {
			$results.IsAccessible | Should Be $true
		}
	}
}
