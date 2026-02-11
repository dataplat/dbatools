#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaComputerCertificate",
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
                "SecurePassword",
                "Certificate",
                "Path",
                "Store",
                "Folder",
                "Flag",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # PowerShell Core (6+) support added via version-specific handling in Add-DbaComputerCertificate

    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $certPath = "$($TestConfig.AppveyorLabRepo)\certificates\localhost.crt"
        $certThumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Certificate is added properly" {
        BeforeAll {
            $results = Add-DbaComputerCertificate -Path $certPath
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $certThumbprint -ErrorAction SilentlyContinue
        }

        It "Should show the proper thumbprint has been added" {
            $results.Thumbprint | Should -Be $certThumbprint
        }

        It "Should be in LocalMachine\My Cert Store" {
            $results.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }
    }

    Context "PFX certificate with chain is imported properly" -Skip:($env:APPVEYOR) {
        BeforeAll {
            # Generate unique temp path for this test run
            $script:tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $script:tempPath -ItemType Directory -Force
            $script:pfxPath = "$script:tempPath\testcert.pfx"

            # Create a secure password for the PFX
            $pfxPassword = ConvertTo-SecureString -String "Test123!@#" -AsPlainText -Force

            # Generate a unique subject name to avoid conflicts
            $script:certSubject = "CN=DbaToolsTest-$(Get-Random)"

            # Create a self-signed certificate using makecert.exe or New-SelfSignedCertificate
            # For PowerShell v3 compatibility, we use New-SelfSignedCertificate if available (Windows 8+)
            # or fall back to creating a cert using X509Certificate2 constructor
            if (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue) {
                # Windows 8+ / Server 2012+ approach
                $splatNewCert = @{
                    Subject           = $script:certSubject
                    CertStoreLocation = "Cert:\CurrentUser\My"
                    KeyExportPolicy   = "Exportable"
                    KeySpec           = "Signature"
                    KeyLength         = 2048
                    KeyAlgorithm      = "RSA"
                    HashAlgorithm     = "SHA256"
                    NotAfter          = (Get-Date).AddDays(1)
                }
                $selfSignedCert = New-SelfSignedCertificate @splatNewCert

                # Export to PFX
                $null = Export-PfxCertificate -Cert $selfSignedCert -FilePath $script:pfxPath -Password $pfxPassword

                # Remove from CurrentUser\My store
                Remove-Item -Path "Cert:\CurrentUser\My\$($selfSignedCert.Thumbprint)" -ErrorAction SilentlyContinue

                $script:testThumbprint = $selfSignedCert.Thumbprint
            } else {
                # For older systems without New-SelfSignedCertificate, skip this test
                Set-ItResult -Skipped -Because "New-SelfSignedCertificate cmdlet not available on this system"
                return
            }

            # Import the PFX using Add-DbaComputerCertificate
            $splatImport = @{
                Path           = $script:pfxPath
                SecurePassword = $pfxPassword
                Confirm        = $false
            }
            $script:importResults = Add-DbaComputerCertificate @splatImport
        }

        AfterAll {
            # Clean up test certificate
            if ($script:testThumbprint) {
                Remove-DbaComputerCertificate -Thumbprint $script:testThumbprint -ErrorAction SilentlyContinue
            }

            # Clean up temp files
            if ($script:tempPath) {
                Remove-Item -Path $script:tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should successfully import the PFX certificate" {
            $script:importResults | Should -Not -BeNullOrEmpty
        }

        It "Should have the correct thumbprint" {
            $script:importResults.Thumbprint | Should -Contain $script:testThumbprint
        }

        It "Should be in LocalMachine\My Cert Store" {
            $script:importResults.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }

        It "Should be able to retrieve the certificate from the store" {
            $retrievedCert = Get-DbaComputerCertificate -Thumbprint $script:testThumbprint
            $retrievedCert | Should -Not -BeNullOrEmpty
            $retrievedCert.Subject | Should -Be $script:certSubject
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Add-DbaComputerCertificate -Path $certPath
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $certThumbprint -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Selected.System.Security.Cryptography.X509Certificates.X509Certificate2"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("FriendlyName", "DnsNameList", "Thumbprint", "NotBefore", "NotAfter", "Subject", "Issuer")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}