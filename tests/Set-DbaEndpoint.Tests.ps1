#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaEndpoint",
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
                "Endpoint",
                "Owner",
                "Type",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually altering an endpoint (owner/type) needs a real endpoint to modify
    # and asserts against live SMO state, so the endpoint-resolution/Alter leg is DEFERRED-TO-GATE.
    # What IS characterizable on a standalone instance is the guard the source runs before any
    # resolution, plus a genuinely silent no-input path: resolution rides
    # foreach ($instance in $SqlInstance) { Get-DbaEndpoint ... }, so an unbound SqlInstance
    # iterates zero times and never reaches Get-DbaEndpoint (probe-verified). Both calls pass
    # WhatIf as belt-and-braces on this Alter command.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the change" {
        It "Stays fully silent when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaEndpoint @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }

        It "Warns once and returns nothing when SqlInstance is supplied without Endpoint or AllEndpoints" {
            $splatNoEndpoint = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaEndpoint @splatNoEndpoint)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter."
        }
    }
}