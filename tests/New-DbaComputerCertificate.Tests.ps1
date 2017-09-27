if (-not $env:appveyor) {
	$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
	Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
	. "$PSScriptRoot\constants.ps1"
	
	Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
		Context "Can generate a new certificate" {
			BeforeAll {
				$cert = New-DbaComputerCertificate -SelfSigned -Silent
			}
			AfterAll {
				Remove-DbaComputerCertificate -Thumbprint $cert.Thumbprint -Confirm:$false
			}
			It "returns the right EnhancedKeyUsageList" {
				"$($cert.EnhancedKeyUsageList)" -match '1\.3\.6\.1\.5\.5\.7\.3\.1' | Should Be $true
			}
			It "returns the right FriendlyName" {
				"$($cert.FriendlyName)" -match 'SQL Server' | Should Be $true
			}
		}
	}
}