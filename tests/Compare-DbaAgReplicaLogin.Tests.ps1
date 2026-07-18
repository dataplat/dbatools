#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaLogin",
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
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the core behavior (comparing logins across 2+ Availability Group replicas)
    # requires a live multi-replica Availability Group, which the standalone InstanceSingle does not
    # provide. Per the coordinator AG policy that leg is DEFERRED-TO-AG01 (a read-only Get/Compare
    # smoke against the lab's AG01 supplies the integration evidence). What IS characterizable on a
    # standalone instance is the pre-comparison guard: the command connects and, before any
    # comparison, warns and returns nothing when the instance is not HADR-enabled, or when no
    # Availability Group matches the requested name.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
    }

    Context "Guarding before the comparison" {
        It "Warns and returns nothing when there is nothing to compare on the instance" {
            # A non-existent Availability Group name exercises the guard regardless of the instance's
            # HADR state: a non-HADR instance warns that HADR is not configured; an HADR instance
            # without that AG warns that no matching group was found. Either way, no object is emitted
            # and the live replica comparison is never reached.
            $splatCompare = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAgReplicaLogin @splatCompare)
            $result.Count | Should -Be 0
            $joinedWarn = $warn -join " "
            if ($isHadrEnabled) {
                $joinedWarn | Should -Match "No Availability Groups found on .* matching the specified criteria"
            } else {
                $joinedWarn | Should -Match "Availability Group \(HADR\) is not configured for the instance"
            }
        }
    }
}
