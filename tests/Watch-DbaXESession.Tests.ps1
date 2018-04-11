$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# This command is special and runs infinitely so don't actually try to run it
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command functions as expected" {
        It "warns if SQL instance version is not supported" {
            $results = Watch-DbaXESession -SqlInstance $script:instance1 -Session system_health -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn -match "Unsupported version" | Should Be $true
        }
    }
}