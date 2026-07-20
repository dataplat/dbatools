#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaServiceMasterKey",
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
                "SecurePassword",
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
    # NOTE ON COVERAGE: creating the key mutates the master database's encryption hierarchy on a
    # shared instance (the port delegates to New-DbaDbMasterKey -Database master), so the live
    # creation is DEFERRED - it needs a disposable instance whose master DB can be freely mutated,
    # which the shared lab instances are not. What IS deterministic and lab-free is the ShouldProcess
    # gate: the command is SupportsShouldProcess and wraps the entire New-DbaDbMasterKey call in
    # $PSCmdlet.ShouldProcess, which under -WhatIf returns false BEFORE any connection is attempted.
    # So -WhatIf against an unreachable instance name proves the gate short-circuits: no output, and
    # crucially no ConnectionError warning (a broken gate would fall through to New-DbaDbMasterKey,
    # attempt the connection to the bogus name, and warn). Lab-free; runs on both gates.
    Context "Honoring -WhatIf before any connection" {
        It "Creates nothing and attempts no connection under -WhatIf" {
            $splatWhatIf = @{
                SqlInstance     = "dbatoolsci-doesnotexist-$(Get-Random)"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(New-DbaServiceMasterKey @splatWhatIf)
            # ShouldProcess returns false under -WhatIf, so the delegated New-DbaDbMasterKey is never
            # reached: nothing is emitted and, because no connection is attempted, no warning fires. A
            # broken gate would fall through and surface a ConnectionError warning for the bogus name.
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }
    }
}