$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		
		It "restarts some services" {
			{ Restart-DbaSqlService -ComputerName $instances -Type SqlAgent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type SqlAgent
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
			
		It "restarts some services through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer | Restart-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
	}
}