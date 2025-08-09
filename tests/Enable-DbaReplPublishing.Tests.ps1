#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplPublishing",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Add-ReplicationLibrary

Describe $CommandName -Tag UnitTests {
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

        foreach ($param in $expected) {
            It "Has parameter: $param" {
                $command | Should -HaveParameter $param
            }
        }

        It "Should have exactly the expected parameters" {
            $hasParameters = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}