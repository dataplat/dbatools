$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$commandname Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Primary', 'PrimarySqlCredential', 'Mirror', 'MirrorSqlCredential', 'Witness', 'WitnessSqlCredential', 'Database', 'SharedPath', 'InputObject', 'UseLastBackup', 'Force', 'EnableException', 'EncryptionAlgorithm', 'EndpointEncryption'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $db1 = "dbatoolsci_mirroring"

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1 -EnableException
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5022 -Owner sa -EnableException
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance3 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5023 -Owner sa -EnableException
    }
    AfterAll {
        $null = Remove-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1 -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1 -Confirm:$false
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -EndPoint dbatoolsci_MirroringEndpoint -Confirm:$false
    }

    It "returns success" {
        $results = Invoke-DbaDbMirroring -Primary $TestConfig.instance2 -Mirror $TestConfig.instance3 -Database $db1 -Confirm:$false -Force -SharedPath C:\temp -WarningVariable warn
        $warn | Should -BeNullOrEmpty
        $results.Status | Should -Be 'Success'
    }
}
