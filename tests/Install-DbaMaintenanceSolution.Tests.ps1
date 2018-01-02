$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Limited testing of Maintenance Solution installer" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")
        }
        AfterAll {
            $server.Databases['tempdb'].Query("DROP TABLE CommandLog")
        }
        It "does not overwrite existing " {
            $results = Install-DbaMaintenanceSolution -SqlInstance $script:instance2 -Database tempdb -WarningVariable warn -WarningAction SilentlyContinue
            $warn -match "already exists" | Should Be $true
        }
    }
}