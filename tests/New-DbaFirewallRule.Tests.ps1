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
                "Method",
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

        $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2

        # Create firewall rules with default Method (Program) and get results for testing
        $resultsNewProgram = New-DbaFirewallRule -SqlInstance $TestConfig.instance2
        $resultsGetProgram = Get-DbaFirewallRule -SqlInstance $TestConfig.instance2

        # Clean up and create port-based rules for testing
        $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2
        $resultsNewPort = New-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Method Port
        $resultsGetPort = Get-DbaFirewallRule -SqlInstance $TestConfig.instance2

        # Test removal
        $resultsRemoveBrowser = $resultsGetPort | Where-Object Type -eq "Browser" | Remove-DbaFirewallRule
        $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2 -Type AllInstance

        $instanceName = ([DbaInstanceParameter]$TestConfig.instance2).InstanceName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.instance2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Program-based rules (default)" {
        # If remote DAC is enabled, also creates rule for DAC.
        It "creates at least two firewall rules" {
            $resultsNewProgram.Count | Should -BeGreaterOrEqual 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNewProgram[0].Successful | Should -Be $true
            $resultsNewProgram[0].Type | Should -Be "Engine"
            $resultsNewProgram[0].DisplayName | Should -Be "SQL Server instance $instanceName"
            $resultsNewProgram[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates program-based rule with Program property set for Engine" {
            $engineRule = $resultsNewProgram | Where-Object Type -eq "Engine"
            $engineRule.Program | Should -Not -BeNullOrEmpty
            $engineRule.Program | Should -BeLike "*sqlservr.exe"
        }

        It "creates second firewall rule for SQL Server Browser" {
            $resultsNewProgram[1].Successful | Should -Be $true
            $resultsNewProgram[1].Type | Should -Be "Browser"
            $resultsNewProgram[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNewProgram[1].Status | Should -Be "The rule was successfully created."
        }

        It "creates program-based rule with Program property set for Browser" {
            $browserRule = $resultsNewProgram | Where-Object Type -eq "Browser"
            $browserRule.Program | Should -Not -BeNullOrEmpty
            $browserRule.Program | Should -BeLike "*sqlbrowser.exe"
        }

        # If remote DAC is enabled, also creates rule for DAC.
        It "returns at least two firewall rules" {
            $resultsGetProgram.Count | Should -BeGreaterOrEqual 2
        }

        It "returns one firewall rule for SQL Server instance with TCP protocol" {
            $resultInstance = $resultsGetProgram | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
        }

        It "returns one firewall rule for SQL Server Browser with UDP protocol" {
            $resultBrowser = $resultsGetProgram | Where-Object Type -eq "Browser"
            $resultBrowser.Protocol | Should -Be "UDP"
        }
    }

    Context "Port-based rules (Method Port)" {
        It "creates at least two port-based firewall rules" {
            $resultsNewPort.Count | Should -BeGreaterOrEqual 2
        }

        It "creates port-based rule with LocalPort property set for Engine" {
            $engineRule = $resultsNewPort | Where-Object Type -eq "Engine"
            $engineRule.LocalPort | Should -Not -BeNullOrEmpty
            $engineRule.Program | Should -BeNullOrEmpty
        }

        It "creates port-based rule with LocalPort 1434 for Browser" {
            $browserRule = $resultsNewPort | Where-Object Type -eq "Browser"
            $browserRule.LocalPort | Should -Be "1434"
            $browserRule.Program | Should -BeNullOrEmpty
        }

        It "returns one firewall rule for SQL Server Browser with port 1434" {
            $resultBrowser = $resultsGetPort | Where-Object Type -eq "Browser"
            $resultBrowser.Protocol | Should -Be "UDP"
            $resultBrowser.LocalPort | Should -Be "1434"
        }
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