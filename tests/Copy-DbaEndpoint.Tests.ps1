$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Endpoint', 'ExcludeEndpoint', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $endpoint = Get-DbaEndpoint -SqlInstance $script:instance2 | Where-Object EndpointType -eq DatabaseMirroring
        $create = $endpoint | Export-DbaScript -Passthru
        $null = $endpoint | Remove-DbaEndpoint -Confirm:$false
        $results = New-DbaEndpoint -SqlInstance $script:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm RC4 -Confirm:$false
    }
    AfterAll {
        if ($create) {
            $null = Get-DbaEndpoint -SqlInstance $script:instance2, $script:instance3 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
            Invoke-DbaQuery -SqlInstance $script:instance2 -Query "$create"
        }
    }

    It "copies an endpoint" {
        $results = Copy-DbaEndpoint -Source $script:instance2 -Destination $script:instance3 -Endpoint Mirroring
        $results.DestinationServer | Should -Be  $script:instance3
        $results.Status | Should -Be 'Successful'
        $results.Name | Should -Be 'Mirroring'
    }
}