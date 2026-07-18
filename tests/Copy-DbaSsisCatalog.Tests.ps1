#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSsisCatalog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Project",
                "Folder",
                "Environment",
                "CreateCatalogPassword",
                "EnableSqlClr",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: copying an SSIS catalog needs the SSIS Catalog SMO assemblies plus a live
    # Source+Destination pair, available only on Windows PowerShell (Desktop) - the live copy is
    # DEFERRED-TO-GATE. What IS deterministic is the edition guard the source runs first: on PowerShell
    # Core the command refuses ($PSVersionTable.PSEdition -eq "Core"). This leg runs on the Core gate
    # (integrationPs7) where the guard fires; skipped on Desktop. WhatIf is belt-and-braces on this copy
    # command, though the guard returns before any action. Probe-verified on Core.
    Context "Guarding on PowerShell Core" {
        It "Warns and returns nothing on PowerShell Core" -Skip:($PSVersionTable.PSEdition -ne "Core") {
            $splatCoreGuard = @{
                Source          = "dbatoolsci-core-src"
                Destination     = "dbatoolsci-core-dst"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Copy-DbaSsisCatalog @splatCoreGuard)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "This command is not supported on Linux or macOS"
        }
    }
}
