Describe "Get-DbaServerOperatingSystem Unit Tests" -Tag "Unittests" {
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
Describe "Get-DbaServerOperatingSystem Integration Test" -Tag "Integrationtests" {
	$result = Get-DbaServerOperatingSystem -ComputerName localhost
	Context "Validate output" {
		it "Should return nothing if unable to connect to server" {
			$result = Get-DbaServerOperatingSystem -ComputerName 'Melton5312'
			$result | Should Be $null
		}
		it "Should return property of Server" {
			$result.Server | Should Not Be $null
		}
	}
}