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
		[object[]]$params = (Get-ChildItem function:\Get-DbaDbStoredProcedure).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemSp', 'Silent'
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
		$results = Get-DbaDbStoredProcedure -SqlInstance $script:instance1 -Database master -ExcludeSystemSp
		it "Should have standard properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance'.Split(',')
			($results[0].PsObject.Properties.Name | Where-Object {$_ -in $ExpectedProps} | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}

		It "Should exclude system stored procedure" {
			($results | Where-Object Name -eq 'sp_helpdb') | Should Be $null
		}
	}
}