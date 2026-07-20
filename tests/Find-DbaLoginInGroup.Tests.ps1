#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
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
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
Integration test should appear below and are custom to the command you are writing.
Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: fully expanding Windows AD group logins needs a domain-joined instance
    # carrying WindowsGroup logins AND live Active Directory to enumerate their members - the
    # standalone lab instances provide neither, so that expansion is DEFERRED (it needs a
    # domain-backed fixture). What IS deterministic and lab-free is the read-only guard the port runs
    # before any enumeration: against an unreachable instance name the command warns once and returns
    # nothing without throwing (EnableException off by default). Two guard branches can produce that
    # single warning and either satisfies the characterization: on an edition where the begin-block
    # Add-Type of System.DirectoryServices.AccountManagement fails the port warns "Failed to load
    # Assembly needed" and returns; otherwise Connect-DbaInstance fails, the catch fires
    # Stop-Function -Category ConnectionError -Continue, and the AD-enumeration loop never runs. The
    # invariant across both branches - no output, at least one warning, no terminating throw - is what
    # this leg pins. Lab-free; runs on both gates.
    Context "Guarding on an unreachable instance" {
        It "Warns and returns nothing when the instance cannot be reached" {
            $splatBadInstance = @{
                SqlInstance     = "dbatoolsci-doesnotexist-$(Get-Random)"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Find-DbaLoginInGroup @splatBadInstance)
            $result.Count | Should -Be 0
            $warn.Count | Should -BeGreaterThan 0
        }
    }
}
