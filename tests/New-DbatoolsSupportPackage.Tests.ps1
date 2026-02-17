#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbatoolsSupportPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Variables",
                "PassThru",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $outputPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $outputPath -ItemType Directory
        $result = New-DbatoolsSupportPackage -Path $outputPath -OutVariable "global:dbatoolsciOutput"
    }

    AfterAll {
        Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "When creating a support package" {
        It "Should return a FileInfo object" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should create a zip file" {
            $result.Extension | Should -Be ".zip"
            $result.Exists | Should -BeTrue
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.IO\.FileInfo"
        }
    }
}