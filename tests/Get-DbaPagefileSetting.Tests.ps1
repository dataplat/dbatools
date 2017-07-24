$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Test" -Tags Unittest {
	Context 'Doing something awesome' {
		It 'It should have tests' {
			$true | Should be $true
		}
	}
}