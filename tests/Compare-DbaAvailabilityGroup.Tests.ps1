#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAvailabilityGroup",
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
                "Type",
                "ExcludeSystemJob",
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: Compare-DbaAvailabilityGroup is the umbrella command - it dispatches by -Type
    # to the Compare-DbaAgReplica{AgentJob,Login,Credential,Operator} sub-commands (default "All" runs
    # all four). Each sub-command carries the same pre-comparison guard. The core comparison across 2+
    # live Availability Group replicas is DEFERRED-TO-AG01 per the coordinator AG policy. What IS
    # characterizable on a standalone instance is the dispatch + guard: a non-existent Availability
    # Group warns once per selected -Type and emits nothing.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
        # the token the sub-commands interpolate into the guard message
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
    }

    Context "Dispatch and guarding before the comparison" {
        It "Warns once and returns nothing for a single -Type when there is nothing to compare" {
            # -Type Login runs exactly one sub-command (Compare-DbaAgReplicaLogin), whose guard fires
            # on the standalone instance: one warning, no output.
            $splatSingle = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                Type              = "Login"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAvailabilityGroup @splatSingle)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            if ($isHadrEnabled) {
                $payload | Should -Be "No Availability Groups found on $instanceToken matching the specified criteria."
            } else {
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }

        It "Fans out -Type All to all four sub-commands, warning once from each" {
            # The default -Type "All" dispatches to AgentJob, Login, Credential, and Operator, so on a
            # standalone instance the guard fires four times - one warning per sub-command, no output.
            $splatAll = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Compare-DbaAvailabilityGroup @splatAll)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 4
            foreach ($record in $warn) {
                $payload = $record.Message -replace "^(\[[^\]]*\]\s*)+", ""
                if ($isHadrEnabled) {
                    $payload | Should -Be "No Availability Groups found on $instanceToken matching the specified criteria."
                } else {
                    $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
                }
            }
        }
    }
}
