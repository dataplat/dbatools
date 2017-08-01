$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Page file settings return proper info" {
		$results = Get-DbaPageFileSetting
		
		if ($results.AutoPageFile) {
			It "returns no filename" {
				$results.FileName | Should Be $null
			}
		}
		else {
			It "return a filename" {
				$results.FileName | Should Not Be $null
			}
		}
	}
}