$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Invoke-DbaCycleErrorLog Unit Tests" -Tag "UnitTests" {
	Context "Validate parameters" {
		$paramCount = 4
		$defaultParamCount = 13
		[object[]]$params = (Get-ChildItem function:\Invoke-DbaCycleErrorLog).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'Type', 'Silent'
		it "Should contian our parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		it "Should only contain our parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}
Describe "Invoke-DbaCycleErrorLog Integration Test" -Tag "IntegrationTests" {
	$results = Invoke-DbaCycleErrorLog -SqlInstance $script:instance1 -Type instance

	Context "Validate output" {
		it "Should have correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,LogType,IsSuccessful,Notes'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}
		it "Should cycle instance error log" {
			$results.LogType | Should Be "instance"
		}
	}
}
