$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Catalog is added properly" {
        # database name is currently fixed
        $database = "SSISDB"
        $db = Get-DbaDatabase -SqlInstance $ssisserver -Database $database

        if (-not $db) {
            $password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
            $results = New-DbaSsisCatalog -SqlInstance $ssisserver -Password $password -WarningAction SilentlyContinue -WarningVariable warn

            # Run the tests only if it worked (this could be more accurate but w/e, it's hard to test on appveyor)
            if ($warn -match "not running") {
                if (-not $env:APPVEYOR_REPO_BRANCH) {
                    Write-Warning "$warn"
                }
            }
            else {
                It "uses the specified database" {
                    $results.SsisCatalog | Should Be $database
                }

                It "creates the catalog" {
                    $results.Created | Should Be $true
                }
                Remove-DbaDatabase -Confirm:$false -SqlInstance $ssisserver -Database $database
            }
        }
    }
}