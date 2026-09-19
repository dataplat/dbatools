#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaComputerCertificate",
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
                "Thumbprint",
                "Store",
                "Folder",
                "DeleteKey",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can remove a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt" -EnableException
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint
        }

        It "returns the store Name" {
            $results.Store | Should -Be "LocalMachine"
        }

        It "returns the folder Name" {
            $results.Folder | Should -Be "My"
        }

        It "reports the proper status of Removed" {
            $results.Status | Should -Be "Removed"
        }

        It "really removed it" {
            $verifyResults = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $verifyResults | Should -BeNullOrEmpty
        }
    }

    Context "Deletes the private key with the certificate when asked" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The file of a machine key sits under RSA\MachineKeys for a legacy CSP key and under Keys for a Key Storage
            # Provider key. Read while the certificate is still in the store, because that is where the key is found from.
            $getKeyFile = {
                param ($Thumbprint)
                $storeCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint"
                $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($storeCert).Key
                $cspFile = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$($key.UniqueName)"
                if (Test-Path -Path $cspFile -PathType Leaf) {
                    $cspFile
                } else {
                    "$env:ProgramData\Microsoft\Crypto\Keys\$($key.UniqueName)"
                }
            }

            # A legacy CSP key that stays because -DeleteKey is not used.
            $keptCert = New-DbaComputerCertificate -SelfSigned
            $keptKeyFile = & $getKeyFile $keptCert.Thumbprint

            # A legacy CSP key, what New-DbaComputerCertificate creates.
            $cspCert = New-DbaComputerCertificate -SelfSigned
            $cspKeyFile = & $getKeyFile $cspCert.Thumbprint

            # A Key Storage Provider key, what New-SelfSignedCertificate creates by default.
            $splatKspCertificate = @{
                DnsName           = $env:COMPUTERNAME
                CertStoreLocation = "Cert:\LocalMachine\My"
                FriendlyName      = "dbatoolsci_deletekey_ksp"
                KeyAlgorithm      = "RSA"
                KeyLength         = 2048
            }
            $kspThumbprint = (New-SelfSignedCertificate @splatKspCertificate).Thumbprint
            $kspKeyFile = & $getKeyFile $kspThumbprint

            # A certificate whose key is shared: the same store entry copied to TrustedPeople points at the same key.
            $sharedCert = New-DbaComputerCertificate -SelfSigned
            $sharedKeyFile = & $getKeyFile $sharedCert.Thumbprint
            $sharedStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($sharedCert.Thumbprint)"
            $trustedPeople = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "TrustedPeople", "LocalMachine"
            $trustedPeople.Open("ReadWrite")
            $trustedPeople.Add($sharedStoreCert)
            $trustedPeople.Close()

            # A certificate whose key is shared with a copy in a folder the StoreName enumeration does not know: WebHosting,
            # where IIS keeps its certificates. Opening the folder for writing creates it on a computer without IIS.
            $webHostingExisted = Test-Path -Path "Cert:\LocalMachine\WebHosting"
            $webHostingCert = New-DbaComputerCertificate -SelfSigned
            $webHostingKeyFile = & $getKeyFile $webHostingCert.Thumbprint
            $webHostingStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($webHostingCert.Thumbprint)"
            $webHosting = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "WebHosting", "LocalMachine"
            $webHosting.Open("ReadWrite")
            $webHosting.Add($webHostingStoreCert)
            $webHosting.Close()

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            foreach ($leftover in $keptCert.Thumbprint, $cspCert.Thumbprint, $kspThumbprint, $sharedCert.Thumbprint, $webHostingCert.Thumbprint) {
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder TrustedPeople -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder WebHosting -DeleteKey -WarningAction SilentlyContinue
            }
            foreach ($keyFile in $keptKeyFile, $cspKeyFile, $kspKeyFile, $sharedKeyFile, $webHostingKeyFile) {
                if (Test-Path -Path $keyFile -PathType Leaf) {
                    [System.IO.File]::Delete($keyFile)
                }
            }
            if (-not $webHostingExisted) {
                # The test created the WebHosting folder, so its registry key goes again.
                [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\SystemCertificates", $true).DeleteSubKeyTree("WebHosting", $false)
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Leaves the private key in place without DeleteKey" {
            $result = Remove-DbaComputerCertificate -Thumbprint $keptCert.Thumbprint
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Kept"
            Test-Path -Path $keptKeyFile -PathType Leaf | Should -BeTrue
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Deletes the legacy CSP key of the certificate" {
            $result = Remove-DbaComputerCertificate -Thumbprint $cspCert.Thumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $cspKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Deletes the Key Storage Provider key of the certificate" {
            $result = Remove-DbaComputerCertificate -Thumbprint $kspThumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $kspKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Keeps a key that another certificate still uses and deletes it with the last one" {
            $result = Remove-DbaComputerCertificate -Thumbprint $sharedCert.Thumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -BeLike "Kept, shared with $($sharedCert.Thumbprint) in Cert:\LocalMachine\TrustedPeople*"
            Test-Path -Path $sharedKeyFile -PathType Leaf | Should -BeTrue

            $lastResult = Remove-DbaComputerCertificate -Thumbprint $sharedCert.Thumbprint -Folder TrustedPeople -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $sharedKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Keeps a key that a certificate in a folder outside the StoreName enumeration still uses" {
            $result = Remove-DbaComputerCertificate -Thumbprint $webHostingCert.Thumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Kept, shared with $($webHostingCert.Thumbprint) in Cert:\LocalMachine\WebHosting"
            Test-Path -Path $webHostingKeyFile -PathType Leaf | Should -BeTrue

            $lastResult = Remove-DbaComputerCertificate -Thumbprint $webHostingCert.Thumbprint -Folder WebHosting -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $webHostingKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}