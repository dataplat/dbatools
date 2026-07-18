#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgReplica",
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
                "AvailabilityGroup",
                "Replica",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually removing a replica requires a live multi-replica Availability
    # Group, which the standalone InstanceSingle does not provide - that leg (and the replica
    # resolution/Drop path) is DEFERRED-TO-AG01 per the coordinator AG policy. What IS
    # characterizable on a standalone instance is the two parameter guards the source runs before
    # any connection or resolution: both fire deterministically regardless of the HADR state on
    # the instance. The resolution leg (SqlInstance + Replica) is intentionally not pinned here: it rides
    # the nested Get-DbaAgReplica -> Get-DbaAvailabilityGroup chain whose behavior is HADR-state
    # dependent, so it belongs with the live AG01 coverage rather than a standalone guess. Both
    # guard calls pass WhatIf as belt-and-braces on this destructive (Drop) command - the guards
    # are plain warnings that return before the gate, so WhatIf cannot change them, and it removes
    # any chance of a real Drop if the environment surprises us with a matching replica.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the removal" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaAgReplica @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Warns once and returns nothing when SqlInstance is supplied without Replica" {
            $splatNoReplica = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaAgReplica @splatNoReplica)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify a replica when using the SqlInstance parameter."
        }
    }
}
