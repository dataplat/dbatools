$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		
		It "stops some services" {
			{ Stop-DbaSqlService -ComputerName $instances -Type SqlAgent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type SqlAgent
			foreach ($service in $services) {
				$service.State | Should Be 'Stopped'
			}
		}
		
		It "starts the services back" {
			{ Start-DbaSqlService -ComputerName $instances -Type SqlAgent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type SqlAgent
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
		
		It "stops specific services based on instance name through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer | Stop-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer
			foreach ($service in $services) {
				$service.State | Should Be 'Stopped'
			}
		}
		
		It "starts the services back through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer | Start-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName MSSQLSERVER -Type SqlAgent,SqlServer
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
	}
}
