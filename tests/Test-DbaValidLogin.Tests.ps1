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
		$paramCount = 7
		$defaultParamCount = 11
		[object[]]$params = (Get-ChildItem function:\Test-DbaValidLogin).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'ExcludeLogin', 'FilterBy', 'IgnoreDomains', 'EnableException'
		It "Should contain our specific parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		It "Should only contain $paramCount parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Command actually works" {
		$results = Test-DbaValidLogin -SqlInstance $script:instance2
		It "Should return correct properties" {
			$ExpectedProps = 'Server,Domain,Login,Type,Found,DisabledInSQLServer,PasswordExpired,LockedOut,Enabled,PasswordNotRequired'.Split(',')
			($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}

		$Type = 'User'
		It "Should return true if Account type is: $Type" {
			($results | Where-Object Type -match $Type) | Should Be $true
		}
		It "Should return true if Account is Found" {
			($results).Found | Should Be $true
		}
		It "Should return true for Server matching: $script:instance2" {
			($results).Server -eq $script:instance2 | Should Be $true
		}
	}
}