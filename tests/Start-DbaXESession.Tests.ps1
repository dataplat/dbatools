$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$systemhealth = Get-DbaXESession -SqlInstance $server -Session system_health
		$started = $systemhealth.IsRunning
		if ($started) {
			$systemhealth.Stop()
		}
	}
	AfterAll {
		if (-not $started) {
			$systemhealth.Stop()
		}
	}
	
	Context "Verifying command works" {
		It "starts the system_health session" {
			$systemhealth | Start-DbaXESession
			$systemhealth.IsRunning | Should Be $true
		}
	}
}