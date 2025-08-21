#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaFirewallRule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Type",
                "Configuration",
                "Force",
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

        $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Confirm:$false

        # Create firewall rules and get results for testing
        $resultsNew = New-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Confirm:$false
        $resultsGet = Get-DbaFirewallRule -SqlInstance $TestConfig.instance2
        $resultsRemoveBrowser = $resultsGet | Where-Object Type -eq "Browser" | Remove-DbaFirewallRule -Confirm:$false
        $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Type AllInstance -Confirm:$false

        $instanceName = ([DbaInstanceParameter]$TestConfig.instance2).InstanceName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # If remote DAC is enabled, also creates rule for DAC.
    It "creates at least two firewall rules" {
        $resultsNew.Count | Should -BeGreaterOrEqual 2
    }

    It "creates first firewall rule for SQL Server instance" {
        $resultsNew[0].Successful | Should -Be $true
        $resultsNew[0].Type | Should -Be "Engine"
        $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsNew[0].Status | Should -Be "The rule was successfully created."
    }

    It "creates second firewall rule for SQL Server Browser" {
        $resultsNew[1].Successful | Should -Be $true
        $resultsNew[1].Type | Should -Be "Browser"
        $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
        $resultsNew[1].Status | Should -Be "The rule was successfully created."
    }

    # If remote DAC is enabled, also creates rule for DAC.
    It "returns at least two firewall rules" {
        $resultsGet.Count | Should -BeGreaterOrEqual 2
    }

    It "returns one firewall rule for SQL Server instance" {
        $resultInstance = $resultsGet | Where-Object Type -eq "Engine"
        $resultInstance.Protocol | Should -Be "TCP"
    }

    It "returns one firewall rule for SQL Server Browser" {
        $resultBrowser = $resultsGet | Where-Object Type -eq "Browser"
        $resultBrowser.Protocol | Should -Be "UDP"
        $resultBrowser.LocalPort | Should -Be "1434"
    }

    It "removes firewall rule for Browser" {
        $resultsRemoveBrowser.Type | Should -Be "Browser"
        $resultsRemoveBrowser.IsRemoved | Should -Be $true
        $resultsRemoveBrowser.Status | Should -Be "The rule was successfully removed."
    }

    # If remote DAC is enabled, removed Engine and DAC. Use foreach when moved to pester5.
    It "removes other firewall rules" {
        $resultsRemove.Type | Should -Contain "Engine"
        $resultsRemove.IsRemoved | Should -Contain $true
        $resultsRemove.Status | Should -Contain "The rule was successfully removed."
    }
}