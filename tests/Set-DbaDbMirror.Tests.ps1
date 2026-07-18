#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMirror",
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
                "Partner",
                "Witness",
                "SafetyLevel",
                "State",
                "InputObject",
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
    # NOTE ON COVERAGE: actually setting mirroring (partner/witness/safety/state) requires a
    # database prepared for mirroring against a live partner instance, which the standalone
    # InstanceSingle does not provide - that leg is DEFERRED-TO-GATE on a mirroring fixture. What
    # IS characterizable on a standalone instance is the guard chain ahead of the change: the
    # no-Database guard, the silent no-match resolution, and a genuinely silent no-input path.
    # This command shares the byte-identical guard + foreach ($instance in $SqlInstance)
    # resolution preamble with Remove-DbaDbMirror and Repair-DbaDbMirror, so an unbound SqlInstance
    # iterates zero times and never reaches Get-DbaDatabase (probe-verified on those two siblings;
    # the Partner/Witness/SafetyLevel/State branches only run for a resolved database, which none
    # of these guard legs produce). Every call passes WhatIf as belt-and-braces on this destructive
    # (ALTER DATABASE SET PARTNER/WITNESS/SAFETY, ChangeMirroringState) command.
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
            $result = @(Set-DbaDbMirror @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }

        It "Warns once and returns nothing when SqlInstance is supplied without Database" {
            $splatNoDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaDbMirror @splatNoDatabase)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Database is required when SqlInstance is specified"
        }

        It "Stays fully silent when the requested database does not exist" {
            # with Database bound the guard passes; resolution rides Get-DbaDatabase, whose
            # Where-Object filter drops a non-matching name silently, so no database resolves and
            # the change loop never runs
            $splatAbsentDb = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "dbatoolsci_nodb_$random"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaDbMirror @splatAbsentDb)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }
    }
}