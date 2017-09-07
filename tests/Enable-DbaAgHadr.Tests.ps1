$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
	Context "Validate parameters" {
		$paramCount = 5
		<# 
			Get commands, Default count = 11
			Commands with SupportShouldProcess = 13
		#>
		$defaultParamCount = 13
		[object[]]$params = (Get-ChildItem function:\Enable-DbaAgHadr).Parameters.Keys
		$knownParameters = 'SqlInstance', 'Credential', 'Force', 'Silent'
		it "Should contian our specifc parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		It "Should only contain $paramCount parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}