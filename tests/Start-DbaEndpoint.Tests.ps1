$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EndPoint', 'AllEndpoints', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint 'TSQL Default TCP' | Stop-DbaEndpoint -Confirm:$false
    }
    AfterAll {
        Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint 'TSQL Default TCP' | Start-DbaEndpoint -Confirm:$false
    }

    It "starts the endpoint" {
        $endpoint = Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint 'TSQL Default TCP'
        $results = $endpoint | Start-DbaEndpoint -Confirm:$false
        $results.EndpointState | Should -Be 'Started'
    }
}
