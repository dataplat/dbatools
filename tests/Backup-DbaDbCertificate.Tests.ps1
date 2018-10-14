$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            (Get-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb) | Remove-DbaDbCertificate -Confirm:$false
            (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb) | Remove-DbaDbMasterKey -Confirm:$false
        }

        $cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -Confirm:$false
        $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Name -Database tempdb
        $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

        It "backs up the db cert" {
            $results.Certificate -match $certificateName1
            $results.Status -match "Success"
        }
    }
}