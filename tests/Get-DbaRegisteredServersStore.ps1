$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Components are properly retreived" {
		
		It "Should return the right values" {
			$results = Get-DbaRegisteredServersStore -SqlInstance localhost\sql2016
			$results.InstanceName | Should Be "SQL2016"
			$results.DisplayName | Should Be "Central Management Servers"
		}
	}
}