$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Endpoint', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Type DatabaseMirroring -Name dbatoolsci_MirroringEndpoint -EnableException -Confirm:$false | Start-DbaEndpoint -EnableException
    }
    AfterAll {
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.instance2 -EndPoint dbatoolsci_MirroringEndpoint -Confirm:$false
    }

    It "returns success" {
        $results = Test-DbaEndpoint -SqlInstance $TestConfig.instance2
        $results | Select-Object -First 1 -ExpandProperty Connection | Should -Be 'Success'
    }
} #$TestConfig.instance2 for appveyor