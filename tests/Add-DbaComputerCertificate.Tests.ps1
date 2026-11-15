#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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

    Context "Flag handling" {
        It "Should not remote import when UserProtected is combined with NonExportable" {
            if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "New-SelfSignedCertificate cmdlet not available on this system"
                return
            }

            if (-not (Get-Command Export-PfxCertificate -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "Export-PfxCertificate cmdlet not available on this system"
                return
            }

            $tempPath = "$($TestConfig.Temp)\$CommandName-Unit-$(Get-Random)"
            $null = New-Item -Path $tempPath -ItemType Directory -Force
            $pfxPath = "$tempPath\testcert.pfx"
            $pfxPassword = ConvertTo-SecureString -String "Test123!@#" -AsPlainText -Force
            $certSubject = "CN=DbaToolsTest-$(Get-Random)"
            $selfSignedCert = $null

            try {
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
                $null = Export-PfxCertificate -Cert $selfSignedCert -FilePath $pfxPath -Password $pfxPassword

                Mock Invoke-Command2 {
                    throw "Invoke-Command2 should not be called when UserProtected is used for a remote computer."
                } -ModuleName dbatools

                $splatAddCertificate = @{
                    ComputerName   = "dbatools-remote"
                    Path           = $pfxPath
                    SecurePassword = $pfxPassword
                    Flag           = @("UserProtected", "NonExportable")
                    Confirm        = $false
                    WarningAction  = "SilentlyContinue"
                    ErrorAction    = "SilentlyContinue"
                }
                $null = Add-DbaComputerCertificate @splatAddCertificate

                Should -Not -Invoke Invoke-Command2 -ModuleName dbatools
            } finally {
                if ($selfSignedCert) {
                    Remove-Item -Path "Cert:\CurrentUser\My\$($selfSignedCert.Thumbprint)" -DeleteKey -ErrorAction SilentlyContinue
                }

                if ($tempPath) {
                    Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
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

    # The skip on this context recorded no reason at all. Unskipped on 2026-08-06 to find out
    # whether one still applies: AppVeyor is gone, but tests\gha.shim.ps1 still sets
    # $env:APPVEYOR, so the gate kept it skipped on the Azure fleet.
    Context "PFX certificate with chain is imported properly" {
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
                Remove-Item -Path "Cert:\CurrentUser\My\$($selfSignedCert.Thumbprint)" -DeleteKey -ErrorAction SilentlyContinue

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
                # DeleteKey, because the import created a private key as well.
                Remove-DbaComputerCertificate -Thumbprint $script:testThumbprint -DeleteKey -ErrorAction SilentlyContinue
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

    Context "Certificate with a private key on the computer of the instance" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For another computer the command imports the certificate in a WinRM session there, and the serializer rebuilds
            # the certificate it returns on this side from its raw data. What belongs to the store entry was lost: HasPrivateKey
            # arrived as False and FriendlyName empty. On CI the instance is local, so the session only happens against a lab
            # whose instance runs on another computer.
            $keyComputerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $keyFriendlyName = "dbatoolsci_add_key_$(Get-Random)"
            $keyTempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $keyTempPath -ItemType Directory -Force
            $keyPfxPath = "$keyTempPath\keycert.pfx"
            $keyPfxPassword = ConvertTo-SecureString -String "Test123!@#" -AsPlainText -Force

            # The PFX is made from a certificate of this computer, which is removed together with its key right away.
            $sourceCert = New-DbaComputerCertificate -SelfSigned -FriendlyName $keyFriendlyName
            $keyThumbprint = $sourceCert.Thumbprint
            $pfxBytes = (Get-Item -Path "Cert:\LocalMachine\My\$keyThumbprint").Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $keyPfxPassword)
            [System.IO.File]::WriteAllBytes($keyPfxPath, $pfxBytes)
            $null = Remove-DbaComputerCertificate -Thumbprint $keyThumbprint -DeleteKey

            $splatAddKeyCertificate = @{
                ComputerName   = $keyComputerName
                Path           = $keyPfxPath
                SecurePassword = $keyPfxPassword
            }
            $beforeAdd = Get-Date
            $keyResults = Add-DbaComputerCertificate @splatAddKeyCertificate
            $afterAdd = Get-Date

            # The key files that were written on this computer during the import and that no certificate uses. Only the window
            # of the import is looked at, so that a test running beside this one does not count. LastWriteTime, because a PFX
            # carries the name of its key container: the import recreates the file that was deleted with the source certificate
            # a moment ago, and NTFS gives the new file the creation time of the deleted one.
            $keyFolders = @(
                "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys",
                "$env:ProgramData\Microsoft\Crypto\Keys",
                "$env:APPDATA\Microsoft\Crypto\RSA",
                "$env:APPDATA\Microsoft\Crypto\Keys"
            )
            $newKeyFiles = @(Get-ChildItem -Path $keyFolders -File -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $PSItem.LastWriteTime -ge $beforeAdd -and $PSItem.LastWriteTime -le $afterAdd })
            $usedKeyNames = foreach ($storeCert in (Get-ChildItem -Path Cert:\LocalMachine, Cert:\CurrentUser -Recurse -ErrorAction SilentlyContinue | Where-Object { $PSItem -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and $PSItem.HasPrivateKey })) {
                try {
                    [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($storeCert).Key.UniqueName
                } catch {
                    # A key that cannot be opened is no key file of this test.
                    $null = 1
                }
            }
            $leftKeyFiles = @($newKeyFiles | Where-Object Name -notin $usedKeyNames)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Remove-DbaComputerCertificate -DeleteKey keeps the key on a remote computer, because the WinRM session cannot
            # open CurrentUser\UserDS (#10823). So the certificate and its key file are removed here.
            $removeCertificateAndKey = {
                param ($Thumbprint)
                $storeCert = Get-Item -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
                if ($storeCert) {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($storeCert)
                    Remove-Item -Path "Cert:\LocalMachine\My\$Thumbprint"
                    if ($rsa) {
                        $keyName = $rsa.Key.UniqueName
                        foreach ($keyFile in "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$keyName", "$env:ProgramData\Microsoft\Crypto\Keys\$keyName") {
                            if (Test-Path -Path $keyFile -PathType Leaf) {
                                [System.IO.File]::Delete($keyFile)
                            }
                        }
                    }
                }
            }
            if ($keyThumbprint) {
                $null = Invoke-Command2 -ComputerName $keyComputerName -ScriptBlock $removeCertificateAndKey -ArgumentList $keyThumbprint
            }
            Remove-Item -Path $keyTempPath -Recurse -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the private key and the friendly name of the certificate" {
            @($keyResults).Count | Should -Be 1
            $keyResults.Thumbprint | Should -Be $keyThumbprint
            $keyResults.HasPrivateKey | Should -Be $true
            $keyResults.FriendlyName | Should -Be $keyFriendlyName
            $keyResults.PSObject.Properties.Name | Should -Not -Contain "HasKey"
            $keyResults.PSObject.Properties.Name | Should -Not -Contain "FriendlyNameValue"
        }

        It "Should leave no copy of the private key on this computer" {
            # The command imports the PFX on this computer first, to send the whole chain to the target computer. That import
            # used PersistKeySet, which left the private key in a key store here on every call.
            $leftKeyFiles.FullName | Should -BeNullOrEmpty
        }
    }
}