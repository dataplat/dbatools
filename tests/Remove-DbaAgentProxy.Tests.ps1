#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentProxy",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Proxy",
                "ExcludeProxy",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL proxyCred WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $server -Query "DROP CREDENTIAL proxyCred;"
    }

    BeforeEach {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $proxyName = "dbatoolsci_test_$(Get-Random)"
        $proxyName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName', @enabled = 1,
        @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_proxy @proxy_name = '$proxyName2', @enabled = 1,
        @description = 'Maintenance tasks on catalog application.', @credential_name = 'proxyCred' ;"
    }

    Context "commands work as expected" {
        It "removes a SQL Agent proxy" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Proxy $proxyName -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName) | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent proxy" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName | Remove-DbaAgentProxy -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName) | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies but excluded" {
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2 -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server -ExcludeProxy $proxyName2) | Should -BeNullOrEmpty
            (Get-DbaAgentProxy -SqlInstance $server -Proxy $proxyName2) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent proxies" {
            (Get-DbaAgentProxy -SqlInstance $server) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentProxy -SqlInstance $server -Confirm:$false
            (Get-DbaAgentProxy -SqlInstance $server) | Should -BeNullOrEmpty
        }
    }
}