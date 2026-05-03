#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Install-DbaParquet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @(
                "Path",
                "Version",
                "LocalFile",
                "Force",
                "EnableException"
            )
            ($expectedParameters | Where-Object { $PSItem -notin $hasParameters }) | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:originalParquetPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsParquet"
    }

    AfterAll {
        Set-DbatoolsConfig -FullName "Path.DbatoolsParquet" -Value $script:originalParquetPath
    }

    Context "NuGet installation" {
        It "installs Parquet.NET and managed dependencies to a custom path" {
            $installPath = Join-Path $TestDrive "parquet"

            $result = Install-DbaParquet -Path $installPath -Force -EnableException

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -BeTrue
            @("Parquet.dll", "Parquet.Net.dll") | Should -Contain $result.Name
            Test-Path -Path $result.Path | Should -BeTrue

            foreach ($assemblyName in "CommunityToolkit.HighPerformance.dll", "K4os.Compression.LZ4.dll", "Snappier.dll", "ZstdSharp.dll") {
                Test-Path -Path (Join-Path $installPath $assemblyName) | Should -BeTrue
            }
        }
    }
}
