$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Endpoint', 'ExcludeEndpoint', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

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