$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		
		It "restarts some services" {
			{ Restart-DbaSqlService -ComputerName $instances -Type Agent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type Agent
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
			
		It "restarts some services through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type Agent,Engine | Restart-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type Agent,Engine
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
	}
}