$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "..\internal\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		
		$instanceName = (Connect-SqlInstance -SqlInstance $script:instance1).ServiceName
		Write-Host $instanceName
		Write-Host $script:instance1
		It "restarts some services" {
			$services = Restart-DbaSqlService -ComputerName $script:instance1 -InstanceName $instanceName -Type Agent
			$services | Should Not Be $null
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
				$service.Status | Should Be 'Successful'
			}
		}
			
		It "restarts some services through pipeline" {
			$services = Get-DbaSqlService -ComputerName $script:instance1 -InstanceName $instanceName -Type Agent, Engine | Restart-DbaSqlService
			$services | Should Not Be $null
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
				$service.Status | Should Be 'Successful'
			}
		}
	}
}