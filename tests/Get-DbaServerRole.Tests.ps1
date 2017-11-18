<#
	The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
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
		$paramCount = x
		$defaultParamCount = 11
		[object[]]$params = (Get-ChildItem function:\Verb-DbaXyz).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'ServerRole', 'ExcludeServerRole'
		It "Should contain our specific parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		It "Should only contain $paramCount parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}

# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Command actually works" {
		$results = Get-DbaServerRole -SqlInstance $script:instance2
		It "Should have correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Id,Role,IsFixedRole,Owner,Member,DateCreated,DateModified'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}

		It "Shows only one value with ServerRole parameter" {
			$results = Get-DbaServerRole -SqlInstance $script:instance2 -ServerRole sysadmin
			$results[0].Role | Should Be "sysadmin"
		}

		It "Returns [sa] member name for sysadmin role" {
			$results.Member -contains "sa" | Should Be $true
		}
	}
}
