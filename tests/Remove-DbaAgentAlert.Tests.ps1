#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Remove-DbaAgentAlert"
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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

        $script:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup any remaining alerts
        $null = Get-DbaAgentAlert -SqlInstance $script:server | Where-Object Name -like "dbatoolsci_test_*" | Remove-DbaAgentAlert -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Commands work as expected" {
        BeforeEach {
            $script:alertName = "dbatoolsci_test_$(Get-Random)"
            $script:alertName2 = "dbatoolsci_test_$(Get-Random)"

            $null = Invoke-DbaQuery -SqlInstance $script:server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$($script:alertName)', @event_description_keyword=N'$($script:alertName)', @severity=25"
            $null = Invoke-DbaQuery -SqlInstance $script:server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$($script:alertName2)', @event_description_keyword=N'$($script:alertName2)', @severity=25"
        }

        It "Removes a SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName) | Should -BeNullOrEmpty
        }

        It "Supports piping SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName | Remove-DbaAgentAlert -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName) | Should -BeNullOrEmpty
        }

        It "Removes all SQL Agent alerts but excluded" {
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName2) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $script:server -ExcludeAlert $script:alertName2) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $script:server -ExcludeAlert $script:alertName2 -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $script:server -ExcludeAlert $script:alertName2) | Should -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $script:server -Alert $script:alertName2) | Should -Not -BeNullOrEmpty
        }

        It "Removes all SQL Agent alerts" {
            (Get-DbaAgentAlert -SqlInstance $script:server) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $script:server -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $script:server) | Should -BeNullOrEmpty
        }
    }
}