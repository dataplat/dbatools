#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Module",
                "Name",
                "Config",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "OutPath",
                "SkipUnchanged",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        It "Returns no output" {
            $outputFile = "$($TestConfig.Temp)\dbatoolsci_exportconfig_$(Get-Random).json"
            $result = Get-DbatoolsConfig | Export-DbatoolsConfig -OutPath $outputFile
            $result | Should -BeNullOrEmpty
            Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
        }
    }
}