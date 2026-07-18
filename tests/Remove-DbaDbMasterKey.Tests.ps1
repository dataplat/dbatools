#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMasterKey",
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
                "Database",
                "ExcludeDatabase",
                "All",
                "InputObject",
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
    # NOTE ON COVERAGE: removing a database master key needs a database that actually has one, so
    # the real removal is DEFERRED-TO-GATE on a master-key fixture. What IS characterizable on any
    # standalone instance is the scope guard the source runs before resolving databases: when
    # -SqlInstance is supplied without -Database, -ExcludeDatabase, or -All, the command refuses to
    # proceed and returns. The guard runs before any connection (probe-verified). WhatIf is passed
    # as belt-and-braces on this destructive (drop master key) command, though the guard returns
    # ahead of any gated action.
    Context "Guarding the database scope" {
        It "Warns once and returns nothing when SqlInstance is supplied without Database, ExcludeDatabase, or All" {
            $splatNoScope = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaDbMasterKey @splatNoScope)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify Database, ExcludeDatabase or All when using SqlInstance"
        }
    }
}