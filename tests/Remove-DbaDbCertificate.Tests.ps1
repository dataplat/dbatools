$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can remove a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master)) {
                $masterkey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            if ($masterKey) { $masterkey | Remove-DbaDatabasemasterKey -Confirm:$false }
        }

        $results = New-DbaDbCertificate -SqlInstance $script:instance1 | Remove-DbaDbCertificate -Confirm:$false

        It "Successfully removes database certificate in master" {
            "$($results.Status)" -match 'Success' | Should Be $true
        }
    }
}