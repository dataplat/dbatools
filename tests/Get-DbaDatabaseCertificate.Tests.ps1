$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Can get a database certificate" {
		BeforeAll {
			$masterKey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
			$null = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database TempDb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
			
			$certificateName1 = "Cert_$(Get-random)"
			$certificateName2 = "Cert_$(Get-random)"
			$null = New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $certificateName1
			$null = New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $certificateName2 -Database "TempDb"
		}
		AfterAll {
			$null = Remove-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName1 -database Master -Confirm:$false
			$null = Remove-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName2 -database TempDb -Confirm:$false
			$null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database TempDb
			if($masterKey) { $null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master }
		}
		
		$cert = Get-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName1		
		It "returns database certificate created in default, master database" {
			"$($cert.Database)" -match 'master' | Should Be $true
		}

		$cert = Get-DbaDatabaseCertificate -SqlInstance $script:instance1 -Database TempDb	
		It "returns database certificate created in TempDb database, looked up by certificate name" {
			"$($cert.Name)" -match $certificateName2 | Should Be $true
		}

		$cert = Get-DbaDatabaseCertificate -SqlInstance $script:instance1 -ExcludeDatabase master
		It "returns database certificates excluding those in the master database" {
			"$($cert.Database)" -notmatch 'master' | Should Be $true
		}

	}
}