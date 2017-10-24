$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	It "returns a datatable" {
		$results.GetType().Name -eq "DataRow" | Should Be $true
	}
	
	It "returns the proper result" {
	}
}
