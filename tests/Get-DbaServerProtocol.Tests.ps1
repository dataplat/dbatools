$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Get some server protocols" {
		$results = Get-DbaServerProtocol
		It "Should return some protocols" {
			$results.Count | Should BeGreaterThan 1
			$results | Where-Object { $_.ProtocolDisplayName -eq 'TCP/IP' } | Should Not Be $null
		}
	}
}