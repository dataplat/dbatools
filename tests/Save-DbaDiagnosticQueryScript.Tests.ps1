#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaDiagnosticQueryScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $tempPath -ItemType Directory -Force
            $result = Save-DbaDiagnosticQueryScript -Path $tempPath
        }

        AfterAll {
            Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Downloads SQL diagnostic query scripts" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Name | Should -BeLike "SQLServerDiagnosticQueries_*.sql"
        }

        It "Downloads files with content" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Length | Should -BeGreaterThan 0
        }
    }
}