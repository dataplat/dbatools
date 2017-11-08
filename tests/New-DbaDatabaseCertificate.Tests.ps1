$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Can create a database certificate" {
		BeforeAll {
			$masterKey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
			$null = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database TempDb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-random)"
            $certificateName2 = "Cert_$(Get-random)"
		}
		AfterAll {
            $null = Remove-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName1 -database Master -Confirm:$false
            $null = Remove-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $certificateName2 -database TempDb -Confirm:$false
            if($masterKey) { $null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database Master }
            $null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database TempDb
        }
        		
        $results = New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $certificateName1
        
		It "Successfully creates a new database certificate in default, master database" {
            "$($results.name)" -match $certificateName1 | Should Be $true
        }
                
        $results = New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $certificateName2 -Database TempDb
		It "Successfully creates a new database certificate in the TempDb database" {
		    "$($results.Database)" -match "TempDb"  | Should Be $true
        }
	}
}