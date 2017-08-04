$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		$results = Get-DbaSqlService -ComputerName $instances
		
		It "shows some services" {
			$results.DisplayName | Should Not Be $null
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent
		
		It "shows only one type of service" {
			foreach ($result in $results) {
				$result.DisplayName -match "Agent" | Should Be $true
			}
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -InstanceName $script:instance1 -Type Agent
		
		It "shows services from a specific instance" {
			foreach ($result in $results) {
				$result.ServiceType| Should Be "SqlAgent" 
			}
		}
				
		$services = Get-DbaSqlService -ComputerName $instances -Type Agent
		
		It "sets startup mode of the services to 'Manual'" {
			foreach ($service in $services) {
				{ $service.ChangeStartMode('Manual') } | Should Not Throw
			}
		}
		
		$results = Get-DbaSqlService -ComputerName $instances -Type Agent
		
		It "verifies that startup mode of the services is 'Manual'" {
			foreach ($result in $results) {
				$result.StartMode | Should Be 'Manual'
			}
		}
		
		$services = Get-DbaSqlService -ComputerName $instances -Type Agent
		
		It "sets startup mode of the services to 'Automatic'" {
			foreach ($service in $services) {
				{ $service.ChangeStartMode('Automatic') } | Should Not Throw
			}
		}
		
		$results = Get-DbaSqlService -ComputerName $instances -Type Agent
			
		It "verifies that startup mode of the services is 'Automatic'" {
			foreach ($result in $results) {
				$result.StartMode | Should Be 'Automatic'
			}
		}
	}
}