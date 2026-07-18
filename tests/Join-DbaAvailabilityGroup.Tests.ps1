#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Join-DbaAvailabilityGroup",
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
                "ClusterType",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually joining a replica to an Availability Group requires a live AG and
    # a second replica-ready instance, which the standalone InstanceSingle does not provide - that
    # leg is DEFERRED-TO-AG01 per the coordinator AG policy. What IS characterizable here is the
    # guard chain ahead of the join: both parameter guards fire before any connection, and the
    # join itself is ShouldProcess-gated with NO pre-join validation of the group name, so under
    # WhatIf the command connects, gates, and finishes fully silent - it never validates, warns,
    # or emits. The join legs pass WhatIf deliberately: without it the command would attempt a
    # real ALTER AVAILABILITY GROUP join on the shared instance (expected to fail, but a mutation
    # attempt regardless), and characterizing the version-dependent SQL error text would pin an
    # unstable surface.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the join" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Join-DbaAvailabilityGroup @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Warns once and returns nothing when SqlInstance is supplied without AvailabilityGroup" {
            $splatNoAgName = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Join-DbaAvailabilityGroup @splatNoAgName)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "No availability group to add"
        }

        It "Connects and stays fully silent under WhatIf when a group name is supplied" {
            # the command performs no existence or HADR validation of the requested group before
            # the gate, so the WhatIf run is the deepest safe probe: connect, gate, skip, emit
            # nothing - no warning even though the group does not exist
            $splatWhatIfJoin = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
                WhatIf            = $true
            }
            $result = @(Join-DbaAvailabilityGroup @splatWhatIfJoin)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }
    }
}
