$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    It "doesn't throw" {
        { Get-DbaOpenTransaction -SqlInstance $script:instance1 } | Should Not Throw
    }
}