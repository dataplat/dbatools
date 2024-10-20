$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Proxy', 'ExcludeProxy', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
    $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
    $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL proxyCred WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
    }


    AfterAll {

        $null = Invoke-DbaQuery -SqlInstance $server -Query "DROP CREDENTIAL proxyCred;"
        }

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $proxyName = "dbatoolsci_test_$(get-random)"
        $proxyName2 = "dbatoolsci_test_$(get-random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName', @enabled = 1,
        @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName2', @enabled = 1,
        @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"
    }

    Context "commands work as expected" {

        It "removes a SQL Agent proxy" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Proxy $proxyName -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName ) | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent proxy" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName ) | Should -Not -BeNullOrEmpty
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Remove-DbaAgentProxy -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName ) | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies but excluded" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 ) | Should -BeNullOrEmpty
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies" {
            (Get-DbaAgentProxy -SqlInstance $server ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server ) | Should -BeNullOrEmpty
        }
    }
}
