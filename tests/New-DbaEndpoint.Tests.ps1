$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $endpoint = Get-DbaEndpoint -SqlInstance $script:instance2 | Where-Object EndpointType -eq DatabaseMirroring
        $create = $endpoint | Export-DbaScript -Passthru
        Get-DbaEndpoint -SqlInstance $script:instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
    }
    AfterAll {
        Get-DbaEndpoint -SqlInstance $script:instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        if ($create) {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Query "$create"
        }
    }
    It "creates an endpoint" {
        $results = New-DbaEndpoint -SqlInstance $script:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm RC4 -Confirm:$false | Start-DbaEndpoint -Confirm:$false
        $results.EndpointType | Should -Be 'DatabaseMirroring'
    }
}