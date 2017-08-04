$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Verifying output" {
		It "runs a specific query" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance1 -QueryName 'Memory Clerk Usage'
			$results.Name.Count | Should Be 1
		}
		It "works with DatabaseSpecific" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance1 -DatabaseSpecific
			$results.Name.Count -gt 10 | Should Be $true
		}
	}
}
