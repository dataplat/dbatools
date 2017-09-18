$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		
		It "stops some services" {
			{ Stop-DbaSqlService -ComputerName $instances -Type Agent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type Agent
			foreach ($service in $services) {
				$service.State | Should Be 'Stopped'
			}
		}
		
		It "starts the services back" {
			{ Start-DbaSqlService -ComputerName $instances -Type Agent } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -Type Agent
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
		
		$server = Connect-DbaSqlServer -SqlInstance $script:instance1
		
		It "stops some services through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName $server.ServiceName -Type Agent,Engine | Stop-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName $server.ServiceName -Type Agent,Engine
			foreach ($service in $services) {
				$service.State | Should Be 'Stopped'
			}
		}
		
		It "starts the services back through pipeline" {
			{ Get-DbaSqlService -ComputerName $instances -InstanceName $server.ServiceName -Type Agent,Engine | Start-DbaSqlService } | Should Not Throw
			$services = Get-DbaSqlService -ComputerName $instances -InstanceName $server.ServiceName -Type Agent,Engine
			foreach ($service in $services) {
				$service.State | Should Be 'Running'
			}
		}
	}
}