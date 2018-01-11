$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

if (-not $env:appveyor) {
    Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
        $results = Get-DbaForceNetworkEncryption $script:instance1 -EnableException

        It "returns true or false" {
            $results.ForceEncryption -ne $null
        }
    }
}