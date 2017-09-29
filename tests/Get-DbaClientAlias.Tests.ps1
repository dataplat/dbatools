$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "adds the alias" {
		$null = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias
		$results = Get-DbaClientAlias
		It "returns accurate information" {
			$results.AliasName -contains 'dbatoolscialias' | Should Be $true
		}
	}
}