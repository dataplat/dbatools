$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Can create a database certificate" {
		BeforeAll {
			$null = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
			$certificateName1 = "Cert_$(Get-random)"
		}
		AfterAll {
			$null = Remove-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $certificateName1 -Database tempdb -Confirm:$false
			$null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb -Confirm:$false
		}
		
		$cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Name $certificateName1 -Database tempdb
		$results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Certificate -Database tempdb
		$null = Remove-Item -Path $results.ExportPath -ErrorAction SilentlyContinue -Confirm:$false
		
		It "backs up the db cert" {
			$results.Certificate -match $certificateName1
			$results.Status -match "Success"
		}
	}
}