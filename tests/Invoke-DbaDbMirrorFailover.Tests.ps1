#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbMirrorFailover",
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
                "InputObject",
                "Force",
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
    # NOTE ON COVERAGE: an actual mirroring failover requires a database mirrored to a live
    # partner instance, which the standalone InstanceSingle does not provide - that leg is
    # DEFERRED-TO-GATE on a mirroring fixture. What IS characterizable here is the one guard the
    # source runs before resolving databases, plus the silent no-match resolution path.
    #
    # INTENTIONAL OMISSION (verified by probe, not assumed): calling the command with NEITHER
    # -SqlInstance nor -InputObject is NOT characterized. Unlike its sibling AG commands, this
    # command has no "you must supply either" guard; with -SqlInstance unbound the first guard is
    # skipped and the body calls Get-DbaDatabase -SqlInstance with a null instance, which raises a
    # parameter-binding error (ParameterArgumentValidationErrorNullNotAllowed). That is an artifact
    # of the missing guard, not intentional command behavior, so it is deliberately left unpinned
    # rather than frozen as a contract.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the failover" {
        It "Warns once and returns nothing when SqlInstance is supplied without Database" {
            # the guard is Test-Bound SqlInstance -and Test-Bound -Not Database, evaluated before
            # any connection, so it fires the same way regardless of whether the instance resolves
            $splatNoDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbMirrorFailover @splatNoDatabase)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Database is required when SqlInstance is specified"
        }

        It "Stays fully silent when the requested database does not exist" {
            # with Database bound the guard passes; resolution rides Get-DbaDatabase, whose
            # Where-Object filter drops a non-matching name silently, so no database resolves and
            # the failover loop never runs
            $splatAbsentDb = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "dbatoolsci_nodb_$random"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaDbMirrorFailover @splatAbsentDb)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }
    }
}
