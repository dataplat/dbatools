#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAgFailover",
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
                "InputObject",
                "Force",
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
    # NOTE ON COVERAGE: an actual failover requires a live multi-replica Availability Group, which
    # the standalone InstanceSingle does not provide - that leg is DEFERRED-TO-AG01 per the
    # coordinator AG policy (the AG01 smoke supplies the live failover evidence). What IS
    # characterizable on a standalone instance is the guard chain that runs BEFORE any failover:
    # two parameter guards that fire before any connection is made, and the resolution path through
    # Get-DbaAvailabilityGroup, which on a non-HADR instance warns once and yields nothing, so the
    # failover loop never runs. Every call below also passes WhatIf: the guards fire either way
    # (they are plain warnings, not gated actions), and a surprise environment with a live matching
    # Availability Group still could not be failed over by a characterization test.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
    }

    Context "Guarding before the failover" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaAgFailover @splatNoInput)
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
            $result = @(Invoke-DbaAgFailover @splatNoAgName)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify at least one availability group when using SqlInstance."
        }

        It "Fails over nothing when the requested Availability Group does not exist" {
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
                WhatIf            = $true
            }
            $result = @(Invoke-DbaAgFailover @splatAbsentAg)
            $result.Count | Should -Be 0

            if ($isHadrEnabled) {
                # An HADR-enabled instance filters the absent name silently: the nested
                # Get-DbaAvailabilityGroup emits no warning for a non-matching name, nothing
                # resolves, and the failover loop never runs.
                $warn.Count | Should -Be 0
            } else {
                # A non-HADR instance warns exactly once, from the nested Get-DbaAvailabilityGroup
                # resolution; Invoke-DbaAgFailover adds no warning of its own and the failover loop
                # never runs.
                $warn.Count | Should -Be 1
                $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }
}
