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
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Version",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
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

            foreach ($assemblyName in "IronCompress.dll", "Microsoft.IO.RecyclableMemoryStream.dll", "Snappier.dll", "ZstdSharp.dll") {
                Test-Path -Path (Join-Path $installPath $assemblyName) | Should -BeTrue
            }
        }

        It "keeps the editions apart by installing below the configured path" {
            # The assemblies are picked for the runtime, so an installation made by the other edition
            # cannot be loaded here. Both editions share the data directory, so they only stay usable
            # side by side while each one installs into its own folder.
            $basePath = Join-Path $TestDrive "editionbase"
            Set-DbatoolsConfig -FullName "Path.DbatoolsParquet" -Value $basePath

            $result = Install-DbaParquet -Force -EnableException

            if ($PSVersionTable.PSEdition -eq "Core") {
                $expectedFolder = "core"
            } else {
                $expectedFolder = "desktop"
            }

            $result.Installed | Should -BeTrue
            Split-Path -Path $result.Path -Parent | Should -Be (Join-Path $basePath $expectedFolder)
        }
    }
}
