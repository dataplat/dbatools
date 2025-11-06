#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "InModule.Commands",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    # The original test used Get-TestConfig, but that is now handled by the test runner
    # and the results are available in $TestConfig.
    # The original test also dynamically set $CommandName, which is now static.

    Context "duplicate commands are not added" {
        It "only indexes one instance per command" {
            # this no longer works in PS 5.1, no idea why, maybe it doesn't like the new test for core or desktop
            # $commandlist = Import-PowerShellDataFile -Path '$PSScriptRoot\..\dbatools.psd1'
            $psd1Path = Join-Path $PSScriptRoot '..\dbatools.psd1'
            $commandlist = Invoke-Expression (Get-Content $psd1Path -Raw)
            $dupes = $commandlist.FunctionsToExport | Group-Object | Where-Object Count -gt 1
            $dupes | Should -BeNullOrEmpty
        }
    }
}