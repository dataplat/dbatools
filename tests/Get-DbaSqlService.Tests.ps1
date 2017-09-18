$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "..\internal\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Command actually works" {
		$instanceName = (Connect-SqlInstance -SqlInstance $script:instance1).ServiceName
		
		$results = Get-DbaSqlService -ComputerName $script:instance1
		
		It "shows some services" {
			$results.DisplayName | Should Not Be $null
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent
		
		It "shows only one type of service" {
			foreach ($result in $results) {
				$result.DisplayName -match "Agent" | Should Be $true
			}
		}
		

		$results = Get-DbaSqlService -ComputerName $script:instance1 -InstanceName $instanceName -Type Agent
		
		It "shows services from a specific instance" {
			foreach ($result in $results) {
				$result.ServiceType| Should Be "Agent" 
			}
		}
				
		$services = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent -InstanceName $instanceName
		
		It "sets startup mode of the services to 'Manual'" {
			foreach ($service in $services) {
				{ $service.ChangeStartMode('Manual') } | Should Not Throw
			}
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent -InstanceName $instanceName 
		
		It "verifies that startup mode of the services is 'Manual'" {
			foreach ($result in $results) {
				$result.StartMode | Should Be 'Manual'
			}
		}
		
		$services = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent -InstanceName $instanceName 
		
		It "sets startup mode of the services to 'Automatic'" {
			foreach ($service in $services) {
				{ $service.ChangeStartMode('Automatic') } | Should Not Throw
			}
		}
		
		$results = Get-DbaSqlService -ComputerName $script:instance1 -Type Agent -InstanceName $instanceName 
			
		It "verifies that startup mode of the services is 'Automatic'" {
			foreach ($result in $results) {
				$result.StartMode | Should Be 'Automatic'
			}
		}
	}
}