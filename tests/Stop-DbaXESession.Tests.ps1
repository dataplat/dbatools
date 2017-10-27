$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$systemhealth = Get-DbaXESession -SqlInstance $server -Session system_health
		$started = $systemhealth.IsRunning
		if (-not $started) {
			$systemhealth.Start()
		}
	}
	AfterAll {
		if ($started) {
			$systemhealth.Start()
		}
	}
	
	Context "Verifying command works" {
		It "stops the system_health session" {
			$systemhealth | Stop-DbaXESession
			$systemhealth.IsRunning | Should Be $false
		}
	}
}