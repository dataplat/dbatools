Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Get-DbaSqlModule Integration Tests" -Tags "IntegrationTests" {
	Context "Modules are properly retreived" {
		
		It "Should have a high count" {
			$results = Get-DbaSqlModule -SqlInstance localhost | Select-Object -First 101
			$results.Count | Should BeGreaterThan 100
		}
		
		$results = Get-DbaSqlModule -SqlInstance localhost -Type View -Database msdb
		It "Should only have one type of object" {
			($results | Select -Unique Database | Measure-Object).Count | Should Be 1
		}
		
		It "Should only have one database" {
			($results | Select -Unique Type | Measure-Object).Count | Should Be 1
		}
	}
}