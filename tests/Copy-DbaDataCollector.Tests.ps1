#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDataCollector",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CollectionSet",
                "ExcludeCollectionSet",
                "NoServerReconfig",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the actual copy migrates Data Collector collection sets from a source to a
    # destination instance, which needs a live Source+Destination pair - that behavior leg is
    # DEFERRED-TO-COPYPAIR (the standing Source+Destination gate pair for the Copy-* family, per the
    # coordinator ruling 2026-07-18). What IS characterizable deterministically is the platform
    # guard the source runs first: on a non-Windows host the command refuses to run because the Core
    # SMOs are unavailable. Per the coordinator ruling this is pinned by flipping the module-scope
    # $script:isWindows state (InModuleScope), never by mocking Connect-DbaInstance (that is the
    # documented mock-coupling latent-red class); the flip is restored in a finally so it cannot
    # leak into other tests.
    Context "Guarding on a non-Windows platform" {
        It "Warns and returns nothing when the host is not Windows" {
            InModuleScope dbatools {
                # [char]39 supplies the apostrophe the source message contains (the contraction of
                # "we are") without a literal apostrophe in the test source
                $q = [char]39
                $originalIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "warn"
                        WarningAction   = "SilentlyContinue"
                        WhatIf          = $true
                    }
                    $result = @(Copy-DbaDataCollector @splatNonWindows)
                    $result.Count | Should -Be 0
                    $warn.Count | Should -Be 1

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                    $payload | Should -Be "Copy-DbaDataCollector does not support Linux - we${q}re still waiting for the Core SMOs from Microsoft"
                } finally {
                    $script:isWindows = $originalIsWindows
                }
            }
        }
    }
}