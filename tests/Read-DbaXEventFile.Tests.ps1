$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Verifying command output" {
		It "returns some results" {
			$results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile -Raw
			[System.Linq.Enumerable]::Count($results) -gt 1 | Should Be $true
		}
		It "returns some results" {
			$results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile
			$results.Count -gt 1 | Should Be $true
		}
	}
}