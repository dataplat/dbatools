#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgListener",
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
                "Listener",
                "Port",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually setting a listener port requires a live Availability Group with a
    # configured listener, which the standalone InstanceSingle does not provide - that leg (and the
    # listener resolution/Alter path) is DEFERRED-TO-AG01 per the coordinator AG policy. What IS
    # characterizable on a standalone instance is the two parameter guards the source runs before
    # any connection or resolution; both fire deterministically regardless of the HADR state.
    # -Port is a Mandatory parameter, so every call supplies it - otherwise PowerShell would prompt
    # and hang a headless gate; supplying it does not change the guard behavior (probe-verified).
    # The resolution leg (SqlInstance + AvailabilityGroup) rides the nested Get-DbaAgListener ->
    # Get-DbaAvailabilityGroup chain whose behavior is HADR-state dependent, so it is not pinned
    # here. Both guard calls pass WhatIf as belt-and-braces on this destructive (Alter) command.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the change" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                Port            = 1433
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaAgListener @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Warns once and returns nothing when SqlInstance is supplied without AvailabilityGroup" {
            $splatNoAgName = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Port            = 1433
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaAgListener @splatNoAgName)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify one or more Availability Groups when using the SqlInstance parameter."
        }
    }
}