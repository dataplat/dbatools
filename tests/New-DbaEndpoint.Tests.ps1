$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Type', 'Protocol', 'Role', 'EndpointEncryption', 'IPAddress', 'EncryptionAlgorithm', 'AuthenticationOrder', 'Certificate', 'Port', 'SslPort', 'Owner', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -EndPoint dbatoolsci_MirroringEndpoint -Confirm:$false
    }

    $results = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Type DatabaseMirroring -Role Partner -Name dbatoolsci_MirroringEndpoint -Confirm:$false | Start-DbaEndpoint -Confirm:$false

    It "creates an endpoint of the db mirroring type" {
        $results.EndpointType | Should -Be 'DatabaseMirroring'
    }
    It "creates it with the right owner" {
        $sa = Get-SaLoginName -SqlInstance $TestConfig.instance2
        $results.Owner | Should -Be $sa
    }
}
