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
    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaComputerCertificateSigningRequest -EnableException
        }

        AfterAll {
            if ($result) {
                $result | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Returns two files per computer (request.inf and .csr)" {
            $result.Count | Should -Be 2
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'Name',
                'FullName',
                'DirectoryName',
                'Length',
                'LastWriteTime',
                'CreationTime',
                'Extension'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }

        It "Creates request.inf configuration file" {
            $result.Name | Should -Contain 'request.inf'
        }

        It "Creates .csr certificate signing request file" {
            $result.Extension | Should -Contain '.csr'
        }
    }

    It "generates a new certificate" {
        $files = New-DbaComputerCertificateSigningRequest
        $files.Count | Should -Be 2
        $filesToRemove += $files
    }
}