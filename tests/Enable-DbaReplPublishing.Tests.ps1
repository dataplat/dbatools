#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Add-ReplicationLibrary

Describe "Enable-DbaReplPublishing" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaReplPublishing
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "SnapshotShare",
                "PublisherSqlLogin",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}