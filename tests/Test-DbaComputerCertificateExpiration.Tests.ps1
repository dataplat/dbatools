#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaComputerCertificateExpiration",
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
                "Type",
                "Threshold"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)

    Context "tests a certificate" {
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "reports that the certificate is expired" {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $results = Test-DbaComputerCertificateExpiration -Thumbprint $thumbprint
            $results | Select-Object -ExpandProperty Note | Should -Be "This certificate has expired and is no longer valid"
            $results.Thumbprint | Should -Be $thumbprint
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            # Use a large threshold to ensure we get output from any certificate on localhost
            $global:dbatoolsciOutput = @(Test-DbaComputerCertificateExpiration -Threshold 36500 | Select-Object -First 1)
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return output" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
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
                "Algorithm",
                "ExpiredOrExpiring",
                "Note"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have the ExpiredOrExpiring property set to true" {
            $global:dbatoolsciOutput[0].ExpiredOrExpiring | Should -BeTrue
        }

        It "Should have a Note property" {
            $global:dbatoolsciOutput[0].Note | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Security\.Cryptography\.X509Certificates\.X509Certificate2"
        }
    }
}