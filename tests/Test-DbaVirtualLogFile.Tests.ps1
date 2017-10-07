<#
	The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
	Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
	Context "Validate parameters" {
		<#
			The $paramCount is adjusted based on the parameters your command will have.

			The $defaultParamCount is adjusted based on what type of command you are writing the test for:
				- Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
				- Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
		#>
		$paramCount = 6
		$defaultParamCount = 11
		[object[]]$params = (Get-ChildItem function:\Test-DbaVirtualLogFile).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystemDbs', 'Silent'
		it "Should contain our specific parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		it "Should only contain $paramCount parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}
# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Command actually works" {
		$results = Get-DbaXyz -ComputerName $script:instance1, $script:instance2
		it "Should have correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Property1,Property2,Property3'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}

		It "Shows only one type of value" {
			foreach ($result in $results) {
				$result.Property1 | Should BeLike "*FilterValue*"
			}
		}
	}
}
