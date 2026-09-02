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

    Context "Running on PowerShell Core" {
        # The SSIS object model is only shipped for Windows PowerShell, so the command has to refuse on pwsh -
        # but it must say so, not claim the caller is on Linux or macOS (#10662).
        It "Refuses with a message that names Windows PowerShell" -Skip:($PSVersionTable.PSEdition -ne "Core") {
            $null = Copy-DbaSsisCatalog -Source dbatoolsci_notconnected -Destination dbatoolsci_notconnected2 -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Windows PowerShell"
            $WarnVar | Should -Not -Match "Linux"
        }
    }
}