#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaComputerCertificate",
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
                "CaServer",
                "CaName",
                "ClusterInstanceName",
                "SecurePassword",
                "FriendlyName",
                "CertificateTemplate",
                "KeyLength",
                "Store",
                "Folder",
                "Flag",
                "Dns",
                "SelfSigned",
                "EnableException",
                "HashAlgorithm",
                "MonthsValid"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

#Tests do not run in appveyor
if (-not $env:appveyor) {
    Describe $CommandName -Tag IntegrationTests {
        Context "Can generate a new certificate with default settings" {
            BeforeAll {
                $defaultCert = New-DbaComputerCertificate -SelfSigned -EnableException -OutVariable "global:dbatoolsciOutput"
            }

            AfterAll {
                Remove-DbaComputerCertificate -Thumbprint $defaultCert.Thumbprint
            }

            It "Returns the right EnhancedKeyUsageList" {
                "$($defaultCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.7\.3\.1" | Should -BeTrue
            }

            It "Returns the right FriendlyName" {
                "$($defaultCert.FriendlyName)" -match "SQL Server" | Should -BeTrue
            }

            It "Returns the right default encryption algorithm" {
                "$(($defaultCert | Select-Object @{n="SignatureAlgorithm";e={$PSItem.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match "sha256RSA" | Should -BeTrue
            }

            It "Returns the right default one year expiry date" {
                $defaultCert.NotAfter -match ((Get-Date).Date).AddMonths(12) | Should -BeTrue
            }
        }

        Context "Can generate a new certificate with custom settings" {
            BeforeAll {
                $customCert = New-DbaComputerCertificate -SelfSigned -HashAlgorithm "Sha256" -MonthsValid 60 -EnableException
            }

            AfterAll {
                Remove-DbaComputerCertificate -Thumbprint $customCert.Thumbprint
            }

            It "Returns the right encryption algorithm" {
                "$(($customCert | Select-Object @{n="SignatureAlgorithm";e={$PSItem.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match "sha256RSA" | Should -BeTrue
            }

            It "Returns the right five year (60 month) expiry date" {
                $customCert.NotAfter -match ((Get-Date).Date).AddMonths(60) | Should -BeTrue
            }
        }

        Context "Output validation" {
            AfterAll {
                $global:dbatoolsciOutput = $null
            }

            It "Should return the correct type" {
                $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "Selected.System.Security.Cryptography.X509Certificates.X509Certificate2"
            }

            It "Should have the correct default display columns" {
                $expectedColumns = @(
                    "FriendlyName",
                    "DnsNameList",
                    "Thumbprint",
                    "NotBefore",
                    "NotAfter",
                    "Subject",
                    "Issuer"
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
}