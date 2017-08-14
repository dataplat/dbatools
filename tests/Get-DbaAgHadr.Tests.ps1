$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Get-DbaAgHadr Unit Tests" -Tag "UnitTests" {
	Context "Validate parameters" {
		$paramCount = 3
		$defaultParamCount = 13
		[object[]]$params = (Get-ChildItem function:\Get-DbaAgHadr).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'AllowException'
		it "Should contian our parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		it "Should only contain our parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}
Describe "Get-DbaAgHadr Integration Test" -Tag "IntegrationTests" {
	$results = Get-DbaAgHadr -SqlInstance $script:instance2

	Context "Validate output" {
		it "Should have correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,IsHadrEnabled'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}
		it "Should return false" {
			$results.IsHadrEnabled | Should Be $false
		}
	}
}
