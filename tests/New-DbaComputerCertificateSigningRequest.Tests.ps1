#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaComputerCertificateSigningRequest",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "ClusterInstanceName",
                "Path",
                "FriendlyName",
                "KeyLength",
                "Dns",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    It "generates a new certificate" {
        $files = New-DbaComputerCertificateSigningRequest
        $files.Count | Should -Be 2
        $filesToRemove += $files
    }

    Context "Output validation" {
        BeforeAll {
            $outputPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $outputPath -ItemType Directory -Force
            $result = New-DbaComputerCertificateSigningRequest -Path $outputPath -EnableException
        }

        AfterAll {
            Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType System.IO.FileInfo
        }

        It "Returns two files per computer" {
            $result.Count | Should -Be 2
        }

        It "Returns the expected file types" {
            $extensions = $result.Extension | Sort-Object
            $extensions | Should -Contain ".inf"
            $extensions | Should -Contain ".csr"
        }
    }
}