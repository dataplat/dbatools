$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Catalog is added properly" {
		# database name is currently fixed
		$database = "SSISDB"
		$db = Get-DbaDatabase -SqlInstance $ssisserver -Database SSISDB
		
		if (-not $db) {
			$password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
			$results = New-DbaSsisCatalog -SqlInstance $ssisserver -Password $password
			
			It "uses the specified database" {
				$results.SsisCatalog | Should Be $database
			}
			
			It "creates the catalog" {
				$results.Created | Should Be $true
			}
			
			Remove-DbaDatabase -SqlInstance $ssisserver -Database $database
		}
	}
}