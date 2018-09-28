$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

if (-not $env:appveyor) {
    Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_publishdacpac"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")
            $publishprofile = New-DbaDacProfile -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
            $dacpac = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Database $dbname -Confirm:$false
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }
        
        It "shows that the update is complete" {
            $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $script:instance2
            $results.Result -match 'Update complete.' | Should Be $true
            if (($dacpac).Path) {
                Remove-Item -Confirm:$false -Path ($dacpac).Path -ErrorAction SilentlyContinue
            }
        }
    }
}