#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAgSpn",
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
                "Credential",
                "AvailabilityGroup",
                "Listener",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the live SPN test walks the Availability Group listeners and resolves
    # their expected service principal names, which requires a live Availability Group with
    # configured listeners - the standalone InstanceSingle does not provide that, so the live leg
    # is DEFERRED-TO-AG01 per the coordinator AG policy. What IS characterizable on a standalone
    # instance is the guard ahead of any listener walk: the no-input guard (connection-
    # independent), and the resolution leg through the compiled Get-DbaAvailabilityGroup, which on
    # a non-HADR instance warns once and yields nothing while an HADR instance filters a
    # non-matching name silently. This command is read-only ([CmdletBinding()] with no
    # SupportsShouldProcess), so no WhatIf is passed.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
        $random = Get-Random
    }

    Context "Guarding before the SPN test" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Test-DbaAgSpn @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Tests nothing when the requested Availability Group does not exist" {
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAgSpn @splatAbsentAg)
            $result.Count | Should -Be 0

            if ($isHadrEnabled) {
                # an HADR instance filters the absent name silently in Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 0
            } else {
                # a non-HADR instance warns exactly once from the nested Get-DbaAvailabilityGroup
                $warn.Count | Should -Be 1
                $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }
}
