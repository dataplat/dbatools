#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJob",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob_disabled
        $sourcejobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance2
        $destjobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance3
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
    }

    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $CommandName
            $hasParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Job",
                "ExcludeJob",
                "DisableOnSource",
                "DisableOnDestination",
                "Force",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Command copies jobs properly" {
        BeforeAll {
            $results = Copy-DbaAgentJob -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Job dbatoolsci_copyjob
        }

        It "returns one success" {
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_disabled | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            $splatCopyJob = @{
                Source               = $TestConfig.instance2
                Destination          = $TestConfig.instance3
                Job                  = "dbatoolsci_copyjob_disabled"
                DisableOnSource      = $true
                DisableOnDestination = $true
                Force                = $true
            }
            $results = Copy-DbaAgentJob @splatCopyJob

            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
        }
    }
}
