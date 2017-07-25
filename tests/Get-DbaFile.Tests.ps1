$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Returns some files" {
		$results = Get-DbaFile -SqlInstance $script:instance1
		It "Should find the master data file" {
			$results.Filename -match 'master.mdf' | Should Be $true
		}
		
		$results = Get-DbaFile -SqlInstance $script:instance1 -Path (Get-DbaDefaultPath -SqlInstance $script:instance1).Log
		It "Should find the master log file" {
			$results.Filename -match 'mastlog.ldf' | Should Be $true
		}
	}
}
