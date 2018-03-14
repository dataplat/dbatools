$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing First Responder Kit installer" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")
        }
        AfterAll {
            $server.Query("ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $server.Query("DROP DATABASE IF EXISTS $database")
        }

        $results = Install-DbaFirstResponderKit -SqlInstance $script:instance2 -Database $database -Branch master

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should Be $true
        }
        It "Shows status of Installed" {
            $results[0].Status -eq "Installed" | Should Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            'sp_Blitz','sp_BlitzIndex' | Should BeIn $results.Name
        }
    }
}