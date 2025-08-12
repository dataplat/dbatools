#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Alert",
                "ExcludeAlert",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up test variables
        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:alertName = "dbatoolsci_test_$(Get-Random)"
        $global:alertName2 = "dbatoolsci_test_$(Get-Random)"
        $global:alertsToCleanup = @()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining alerts
        if ($global:alertsToCleanup.Count -gt 0) {
            Remove-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertsToCleanup -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Clean up specific test alerts if they still exist
        Remove-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName, $global:alertName2 -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When removing SQL Agent alerts" {
        BeforeEach {
            # Create test alerts for each test
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            
            $null = Invoke-DbaQuery -SqlInstance $global:server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$($global:alertName)', @event_description_keyword=N'$($global:alertName)', @severity=25"
            $null = Invoke-DbaQuery -SqlInstance $global:server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$($global:alertName2)', @event_description_keyword=N'$($global:alertName2)', @severity=25"
            
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            # Clean up test alerts after each test
            Remove-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName, $global:alertName2 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "removes a SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName) | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName | Remove-DbaAgentAlert -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName) | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts but excluded" {
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName2) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $global:server -ExcludeAlert $global:alertName2) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $global:server -ExcludeAlert $global:alertName2 -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $global:server -ExcludeAlert $global:alertName2) | Should -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $global:server -Alert $global:alertName2) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts" {
            (Get-DbaAgentAlert -SqlInstance $global:server) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $global:server -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $global:server) | Should -BeNullOrEmpty
        }
    }
}
