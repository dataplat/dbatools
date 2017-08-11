$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Can get a certificate" {
		BeforeAll {
			$cert = New-DbaComputerCertificate -SelfSigned -Silent
		}
		AfterAll {
			$cert | Remove-DbaComputerCertificate -Confirm:$false
		}
		
		$results = Get-DbaComputerCertificate
		
		It "Should show the proper thumbprint has been added" {
			"$($results.Thumbprint)" -match $cert.Thumbprint | Should Be $true
		}
		It "Should show the proper thumbprint has been added" {
			"$($results.EnhancedKeyUsageList)" -match '1\.3\.6\.1\.5\.5\.7\.3\.1' | Should Be $true
		}
	}
}