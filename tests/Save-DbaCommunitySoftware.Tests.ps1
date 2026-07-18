#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaCommunitySoftware",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Software",
                "Branch",
                "LocalFile",
                "Url",
                "LocalDirectory",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: downloading and unpacking community software reaches out to GitHub (and for
    # some software the GitHub releases API), so the real download legs need network access and
    # external services - those are DEFERRED-TO-GATE (a networked runner). What IS characterizable
    # locally, with no instance and no network, is the LocalFile guard: for MaintenanceSolution the
    # source only composes URL strings (no web request) and then, when -LocalFile is supplied,
    # validates the file exists before doing anything - a nonexistent path warns and returns before
    # any download. This leg needs no SQL instance. WhatIf is passed as belt-and-braces on this
    # file-writing command, though the guard returns ahead of any write.
    BeforeAll {
        $random = Get-Random
        $missingLocalFile = Join-Path $env:TEMP "dbatoolsci_missing_$random.zip"
        # [char]39 supplies the apostrophe the source message contains (the contraction in "does
        # not exist") without putting a literal apostrophe in the test source
        $apostrophe = [char]39
    }

    Context "Guarding a missing LocalFile" {
        It "Warns and returns nothing when the supplied LocalFile does not exist" {
            $splatMissing = @{
                Software        = "MaintenanceSolution"
                LocalFile       = $missingLocalFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Save-DbaCommunitySoftware @splatMissing)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "$missingLocalFile doesn${apostrophe}t exist"
        }
    }
}