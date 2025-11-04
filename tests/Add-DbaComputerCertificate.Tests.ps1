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

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)

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

    Context "PFX certificate with chain is imported properly" {
        BeforeAll {
            # Generate unique temp path for this test run
            $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $tempPath -ItemType Directory -Force
            $pfxPath = "$tempPath\testcert.pfx"

            # Create a secure password for the PFX
            $pfxPassword = ConvertTo-SecureString -String "Test123!@#" -AsPlainText -Force

            # Generate a unique subject name to avoid conflicts
            $certSubject = "CN=DbaToolsTest-$(Get-Random)"

            # Create a self-signed certificate using makecert.exe or New-SelfSignedCertificate
            # For PowerShell v3 compatibility, we use New-SelfSignedCertificate if available (Windows 8+)
            # or fall back to creating a cert using X509Certificate2 constructor
            if (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue) {
                # Windows 8+ / Server 2012+ approach
                $splatNewCert = @{
                    Subject           = $certSubject
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
                $null = Export-PfxCertificate -Cert $selfSignedCert -FilePath $pfxPath -Password $pfxPassword

                # Remove from CurrentUser\My store
                Remove-Item -Path "Cert:\CurrentUser\My\$($selfSignedCert.Thumbprint)" -ErrorAction SilentlyContinue

                $testThumbprint = $selfSignedCert.Thumbprint
            } else {
                # For older systems without New-SelfSignedCertificate, skip this test
                Set-ItResult -Skipped -Because "New-SelfSignedCertificate cmdlet not available on this system"
                return
            }

            # Import the PFX using Add-DbaComputerCertificate
            $splatImport = @{
                Path           = $pfxPath
                SecurePassword = $pfxPassword
                Confirm        = $false
            }
            $importResults = Add-DbaComputerCertificate @splatImport
        }

        AfterAll {
            # Clean up test certificate
            if ($testThumbprint) {
                Remove-DbaComputerCertificate -Thumbprint $testThumbprint -ErrorAction SilentlyContinue
            }

            # Clean up temp files
            if ($tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should successfully import the PFX certificate" {
            $importResults | Should -Not -BeNullOrEmpty
        }

        It "Should have the correct thumbprint" {
            $importResults.Thumbprint | Should -Contain $testThumbprint
        }

        It "Should be in LocalMachine\My Cert Store" {
            $importResults.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }

        It "Should be able to retrieve the certificate from the store" {
            $retrievedCert = Get-DbaComputerCertificate -Thumbprint $testThumbprint
            $retrievedCert | Should -Not -BeNullOrEmpty
            $retrievedCert.Subject | Should -Be $certSubject
        }
    }
}