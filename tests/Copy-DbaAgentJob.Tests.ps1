#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Copy-DbaAgentJob" -Tag "IntegrationTests" {
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
            $command = Get-Command Copy-DbaAgentJob
            $expected = $TestConfig.CommonParameters

            $expected += @(
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
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
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
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Job = "dbatoolsci_copyjob_disabled"
                DisableOnSource = $true
                DisableOnDestination = $true
                Force = $true
            }
            $results = Copy-DbaAgentJob @splatCopyJob

            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
        }
    }
}
