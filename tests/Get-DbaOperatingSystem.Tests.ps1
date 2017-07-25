$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Get-DbaOperatingSystem Unit Tests" -Tag "UnitTests" {
	InModuleScope dbatools {
		Context "Validate parameters" {
			$params = (Get-ChildItem function:\Get-DbaServerOperatingSystem).Parameters	
			it "should have a parameter named ComputerName" {
				$params.ContainsKey("ComputerName") | Should Be $true
			}
			it "should have a parameter named Credential" {
				$params.ContainsKey("Credential") | Should Be $true
			}
			it "should have a parameter named Silent" {
				$params.ContainsKey("Silent") | Should Be $true
			}
		}
		Context "Validate input" {
			it "Cannot resolve hostname of computer" {
				mock Resolve-DbaNetworkName {$null}
				{Get-DbaServerOperatingSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
			}
		}
	}
}
Describe "Get-DbaServerOperatingSystem Integration Test" -Tag "IntegrationTests" {
	$result = Get-DbaServerOperatingSystem -ComputerName $script:instance1

	$props = 'ComputerName','Server','SqlInstance','Manufacturer','OSArchitecture',
		'BuildNumber','Version','InstallDate','LastBootUpTime','LocalDateTime','BootDevice',
		'TimeZone','TimeZoneDaylight','TimeZoneStandard','TotalVisibleMemorySize'
	<#
		FreePhysicalMemory: units = KB
		FreeVirtualMemory: units = KB
		TimeZoneStandard: StandardName from win32_timezone
		TimeZoneDaylight: DaylightName from win32_timezone
		TimeZone: Caption from win32_timezone
	#>
	Context "Validate output" {
		foreach ($prop in $props) {
			$p = $result.PSObject.Properties[$prop]
			it "Should return property: $prop" {
				$p.Name | Should Not Be $prop
			}
		}
		it "Should return nothing if unable to connect to server" {
			$result = Get-DbaServerOperatingSystem -ComputerName 'Melton5312'
			$result | Should Be $null
		}
	}
}