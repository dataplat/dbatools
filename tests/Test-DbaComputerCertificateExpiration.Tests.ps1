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
            $script:outputForValidation = Test-DbaComputerCertificateExpiration -Thumbprint $thumbprint
            $script:outputForValidation | Select-Object -ExpandProperty Note | Should -Be "This certificate has expired and is no longer valid"
            $script:outputForValidation.Thumbprint | Should -Be $thumbprint
        }

        Context "Output validation" {
            It "Returns output with expected properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $script:outputForValidation.ExpiredOrExpiring | Should -BeTrue
                $script:outputForValidation.Note | Should -Not -BeNullOrEmpty
            }

            It "Has the expected default display properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $defaultProps = $script:outputForValidation[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @(
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
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }
        }
    }
}