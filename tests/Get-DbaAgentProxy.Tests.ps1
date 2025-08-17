#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentProxy",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        $tUserName = "dbatoolsci_proxytest"
        $proxyName1 = "STIG"
        $proxyName2 = "STIGX"

        $null = New-LocalUser -Name $tUserName -Password $tPassword -Disabled:$false
        $splatCredential = @{
            SqlInstance = $TestConfig.instance2
            Name        = $tUserName
            Identity    = "$env:COMPUTERNAME\$tUserName"
            Password    = $tPassword
        }
        $null = New-DbaCredential @splatCredential

        $splatProxy1 = @{
            SqlInstance     = $TestConfig.instance2
            Name            = $proxyName1
            ProxyCredential = $tUserName
        }
        $null = New-DbaAgentProxy @splatProxy1

        $splatProxy2 = @{
            SqlInstance     = $TestConfig.instance2
            Name            = $proxyName2
            ProxyCredential = $tUserName
        }
        $null = New-DbaAgentProxy @splatProxy2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $tUserName = "dbatoolsci_proxytest"
        $proxyName1 = "STIG"
        $proxyName2 = "STIGX"

        Remove-LocalUser -Name $tUserName -ErrorAction SilentlyContinue
        $credential = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name $tUserName
        if ($credential) {
            $credential.DROP()
        }
        $proxy = Get-DbaAgentProxy -SqlInstance $TestConfig.instance2 -Proxy $proxyName1, $proxyName2
        if ($proxy) {
            $proxy.DROP()
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Gets the list of Proxy" {
        BeforeAll {
            $proxyName1 = "STIG"
            $results = @(Get-DbaAgentProxy -SqlInstance $TestConfig.instance2)
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the name STIG" {
            $results.Name | Should -Contain $proxyName1
        }

        It "Should be enabled" {
            $results.IsEnabled | Should -Contain $true
        }
    }

    Context "Gets a single Proxy" {
        BeforeAll {
            $proxyName1 = "STIG"
            $results = Get-DbaAgentProxy -SqlInstance $TestConfig.instance2 -Proxy $proxyName1
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the name STIG" {
            $results.Name | Should -BeExactly $proxyName1
        }

        It "Should be enabled" {
            $results.IsEnabled | Should -BeTrue
        }
    }

    Context "Gets the list of Proxy without excluded" {
        BeforeAll {
            $proxyName1 = "STIG"
            $results = @(Get-DbaAgentProxy -SqlInstance $TestConfig.instance2 -ExcludeProxy $proxyName1)
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should not have the name STIG" {
            $results.Name | Should -Not -Contain $proxyName1
        }

        It "Should be enabled" {
            $results.IsEnabled | Should -Contain $true
        }
    }
}