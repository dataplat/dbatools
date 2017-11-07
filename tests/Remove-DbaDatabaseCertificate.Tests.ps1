$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Can remove a database certificate" {
		BeforeAll {
			$masterKey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
			
			$certificateName1 = "Cert_$(Get-random)"
			$null = New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $certificateName1
		}
		AfterAll {
			if($masterKey) { $null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master }
		}
		
		$results = Remove-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName1 -database Master -Confirm:$false
		It "Successfully removes database certificate in master" {
			"$($results.Status)" -match 'Success' | Should Be $true
		}
	}
}