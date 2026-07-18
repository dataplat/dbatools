#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAvailabilityGroup",
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
                "Secondary",
                "SecondarySqlCredential",
                "AddDatabase",
                "SeedingMode",
                "SharedPath",
                "UseLastBackup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the actual readiness test (replica connection state, seeding/backup
    # prerequisites) requires a live Availability Group across a primary and one or more
    # secondaries, which the standalone InstanceSingle does not provide - that leg is
    # DEFERRED-TO-AG01 per the coordinator AG policy. Both -SqlInstance and -AvailabilityGroup are
    # Mandatory and the command connects before any guard, so there is no connection-independent
    # leg; what IS deterministic on any single reachable instance is the not-found guard: a
    # nonexistent Availability Group name yields exactly one "not found" warning and no output,
    # regardless of the HADR state on the instance (a non-HADR instance throws inside the EnableException
    # Get-DbaAvailabilityGroup and is caught into the same not-found message; an HADR instance
    # simply resolves nothing). This command is read-only ([CmdletBinding()] with no
    # SupportsShouldProcess), so no WhatIf is passed. The message interpolates the connected server
    # object, reproduced here from the same Connect-DbaInstance result.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
    }

    Context "Guarding before the readiness test" {
        It "Warns once and returns nothing when the requested Availability Group does not exist" {
            $agName = "dbatoolsci_noag_$random"
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = $agName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
            }
            $result = @(Test-DbaAvailabilityGroup @splatAbsentAg)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Availability Group $agName not found on $server."
        }
    }
}