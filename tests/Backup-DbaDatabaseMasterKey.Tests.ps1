$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb)) {
                $masterkey = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
        }
        AfterAll {
            (Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb) | Remove-DbaDatabaseMasterKey -Confirm:$false
        }

        $results = Backup-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
        $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

        It "backs up the db cert" {
            $results.Database -eq 'tempdb'
            $results.Status -eq "Success"
        }
    }
}