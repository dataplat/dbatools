$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		$results = Get-DbaSqlService -ComputerName $script:instance1, $script:instance2
		
		It "shows some services" {
			$results.DisplayName | Should Not Be $null
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent
		
		It "shows only one type of service" {
			foreach ($result in $results) {
				$result.DisplayName -match "Agent" | Should Be $true
			}
		}
	}
}