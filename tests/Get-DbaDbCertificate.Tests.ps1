$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can get a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master)) {
                $masterkey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $tempdbmasterkey = New-DbaDatabasemasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-random)"
            $certificateName2 = "Cert_$(Get-random)"
            $cert1 = New-DbaDbCertificate -SqlInstance $script:instance1 -Name $certificateName1
            $cert2 = New-DbaDbCertificate -SqlInstance $script:instance1 -Name $certificateName2 -Database "tempdb"
        }
        AfterAll {
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDatabaseMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDatabasemasterKey -Confirm:$false }
        }

        $cert = Get-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $certificateName1
        It "returns database certificate created in default, master database" {
            "$($cert.Database)" -match 'master' | Should Be $true
        }

        $cert = Get-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb
        It "returns database certificate created in tempdb database, looked up by certificate name" {
            "$($cert.Name)" -match $certificateName2 | Should Be $true
        }

        $cert = Get-DbaDbCertificate -SqlInstance $script:instance1 -ExcludeDatabase master
        It "returns database certificates excluding those in the master database" {
            "$($cert.Database)" -notmatch 'master' | Should Be $true
        }

    }
}