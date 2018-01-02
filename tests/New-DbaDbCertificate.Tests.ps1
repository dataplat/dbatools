$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master)) {
                $masterkey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $tempdbmasterkey = New-DbaDatabasemasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-random)"
            $certificateName2 = "Cert_$(Get-random)"
        }
        AfterAll {
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDatabaseMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDatabasemasterKey -Confirm:$false }
        }

        $cert1 = New-DbaDbCertificate -SqlInstance $script:instance1 -Name $certificateName1
        It "Successfully creates a new database certificate in default, master database" {
            "$($cert1.name)" -match $certificateName1 | Should Be $true
        }

        $cert2 = New-DbaDbCertificate -SqlInstance $script:instance1 -Name $certificateName2 -Database tempdb
        It "Successfully creates a new database certificate in the tempdb database" {
            "$($cert2.Database)" -match "tempdb" | Should Be $true
        }

        $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
        $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
    }
}