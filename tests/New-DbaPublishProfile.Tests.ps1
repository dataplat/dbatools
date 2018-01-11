$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_publishprofile"
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = $server.Query("Create Database [$dbname]")
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
        $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    It "returns the right results" {
        $publishprofile = New-DbaPublishProfile -SqlInstance $script:instance1 -Database $dbname
        $publishprofile.FileName -match 'publish.xml' | Should Be $true
        Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
    }
}