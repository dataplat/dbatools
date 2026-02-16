#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaComputerCertificate",
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
                "Store",
                "Folder",
                "Path",
                "Thumbprint",
                "EnableException",
                "Type"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)

    Context "Can get a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"

            # Get all certificates once for testing
            $allCertificates = Get-DbaComputerCertificate -OutVariable "global:dbatoolsciOutput"
            $specificCertificate = Get-DbaComputerCertificate -Thumbprint $thumbprint
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -ErrorAction SilentlyContinue
        }

        It "returns a single certificate with a specific thumbprint" {
            $specificCertificate.Thumbprint | Should -Be $thumbprint
        }

        It "returns all certificates and at least one has the specified thumbprint" {
            "$($allCertificates.Thumbprint)" -match $thumbprint | Should -Be $true
        }

        It "returns all certificates and at least one has the specified EnhancedKeyUsageList" {
            "$($allCertificates.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.7\.3\.1" | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Security.Cryptography.X509Certificates.X509Certificate2]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "Store",
                "Folder",
                "Name",
                "DnsNameList",
                "Thumbprint",
                "NotBefore",
                "NotAfter",
                "Subject",
                "Issuer",
                "Algorithm"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Security\.Cryptography\.X509Certificates\.X509Certificate2"
        }
    }
}