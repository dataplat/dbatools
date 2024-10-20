param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentProxy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentProxy
        }
        
        It "has the required parameter: SqlInstance" {
            $CommandUnderTest | Should -HaveParameter "SqlInstance"
        }
        
        It "has the required parameter: SqlCredential" {
            $CommandUnderTest | Should -HaveParameter "SqlCredential"
        }
        
        It "has the required parameter: Proxy" {
            $CommandUnderTest | Should -HaveParameter "Proxy"
        }
        
        It "has the required parameter: ExcludeProxy" {
            $CommandUnderTest | Should -HaveParameter "ExcludeProxy"
        }
        
        It "has the required parameter: InputObject" {
            $CommandUnderTest | Should -HaveParameter "InputObject"
        }
        
        It "has the required parameter: EnableException" {
            $CommandUnderTest | Should -HaveParameter "EnableException"
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL proxyCred WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
        }

        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $server -Query "DROP CREDENTIAL proxyCred;"
        }

        BeforeEach {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $proxyName = "dbatoolsci_test_$(Get-Random)"
            $proxyName2 = "dbatoolsci_test_$(Get-Random)"

            $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName', @enabled = 1,
            @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"

            $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName2', @enabled = 1,
            @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"
        }

        It "removes a SQL Agent proxy" {
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Proxy $proxyName -Confirm:$false
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent proxy" {
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Should -Not -BeNullOrEmpty
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Remove-DbaAgentProxy -Confirm:$false
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies but excluded" {
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2 | Should -Not -BeNullOrEmpty
            Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 -Confirm:$false
            Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 | Should -BeNullOrEmpty
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2 | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies" {
            Get-DbaAgentProxy -SqlInstance $server | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Confirm:$false
            Get-DbaAgentProxy -SqlInstance $server | Should -BeNullOrEmpty
        }
    }
}
