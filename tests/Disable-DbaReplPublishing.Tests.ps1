#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaReplPublishing",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

Describe $CommandName -Tag IntegrationTests {
    # An instance that is not a publisher needs no replication setup, so these tests run on InstanceSingle.
    It "Runs against an instance that is not a publisher" {
        (Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle).IsPublisher | Should -BeFalse
    }

    # The check used Stop-Function -Continue -ContinueLabel main, and no loop of the command carries that
    # label. A labeled continue that matches no loop leaves the command and ends the whole calling script.
    It "Warns about an instance that is not a publisher without ending the caller loop" {
        $loopCount = 0
        foreach ($i in 1..3) {
            $null = Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $loopCount++
        }
        $loopCount | Should -Be 3
        $WarnVar | Should -BeLike "*isn't currently enabled for publishing*"
    }

    It "Warns only about the connection when the instance cannot be reached" {
        $null = Disable-DbaReplPublishing -SqlInstance "dbatoolsci-nohost-$(Get-Random)" -WarningAction SilentlyContinue
        $WarnVar -like "*Error connecting to*" | Should -Not -BeNullOrEmpty
        $WarnVar -like "*enabled for publishing*" | Should -BeNullOrEmpty
    }
}