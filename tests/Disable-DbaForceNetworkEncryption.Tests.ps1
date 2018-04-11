$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    $results = Disable-DbaForceNetworkEncryption $script:instance1 -EnableException

    It "returns false" {
        $results.ForceEncryption -eq $false
    }
}