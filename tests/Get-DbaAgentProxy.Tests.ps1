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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
        $userName = "user_$(Get-Random)"
        $password = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        $identity = "$computerName\$userName"
        $proxyName1 = "proxy_$(Get-Random)"
        $proxyName2 = "proxy_$(Get-Random)"

        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { New-LocalUser -Name $args[0] -Password $args[1] -Disabled:$false }
            ArgumentList = $userName, $password
        }
        Invoke-Command2 @splatInvoke

        $splatCredential = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $userName
            Identity    = $identity
            Password    = $password
        }
        $null = New-DbaCredential @splatCredential

        $splatProxy1 = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Name            = $proxyName1
            ProxyCredential = $userName
        }
        $null = New-DbaAgentProxy @splatProxy1

        $splatProxy2 = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Name            = $proxyName2
            ProxyCredential = $userName
        }
        $null = New-DbaAgentProxy @splatProxy2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { Remove-LocalUser -Name $args[0] -ErrorAction SilentlyContinue }
            ArgumentList = $userName
        }
        Invoke-Command2 @splatInvoke

        $null = Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Name $userName | Remove-DbaCredential
        $null = Get-DbaAgentProxy -SqlInstance $TestConfig.InstanceSingle -Proxy $proxyName1, $proxyName2 | Remove-DbaAgentProxy

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the list of Proxy" {
        BeforeAll {
            $results = Get-DbaAgentProxy -SqlInstance $TestConfig.InstanceSingle
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
            $results = Get-DbaAgentProxy -SqlInstance $TestConfig.InstanceSingle -Proxy $proxyName1
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
            $results = Get-DbaAgentProxy -SqlInstance $TestConfig.InstanceSingle -ExcludeProxy $proxyName1
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