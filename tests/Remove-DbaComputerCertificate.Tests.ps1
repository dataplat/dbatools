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

            # A certificate whose key is shared with a copy in a custom folder that the caller is not allowed to read.
            # The folder is still listed under Cert:\LocalMachine, but opening it fails, so the scan for shared keys is
            # incomplete and the key has to stay. Read access is taken away with a deny rule on the registry key of the
            # folder; the rule leaves ReadPermissions and ChangePermissions alone, so the same account can remove it again.
            $unreadableFolder = "dbatoolsci_unreadable"
            $unreadableCert = New-DbaComputerCertificate -SelfSigned
            $unreadableKeyFile = & $getKeyFile $unreadableCert.Thumbprint
            $unreadableStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($unreadableCert.Thumbprint)"
            $unreadableStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $unreadableFolder, "LocalMachine"
            $unreadableStore.Open("ReadWrite")
            $unreadableStore.Add($unreadableStoreCert)
            $unreadableStore.Close()
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList $currentUser, "QueryValues, EnumerateSubKeys", "ContainerInherit", "None", "Deny"
            # Set-Acl cannot restore the rule, because it opens the key with the read rights the rule denies.
            $setUnreadableFolderDenyRule = {
                param ($Present)
                $registryRights = [System.Security.AccessControl.RegistryRights]"ReadPermissions, ChangePermissions"
                $registryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\SystemCertificates\$unreadableFolder", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $registryRights)
                $registrySecurity = $registryKey.GetAccessControl()
                if ($Present) {
                    $registrySecurity.AddAccessRule($denyRule)
                } else {
                    $null = $registrySecurity.RemoveAccessRule($denyRule)
                }
                $registryKey.SetAccessControl($registrySecurity)
                $registryKey.Close()
            }

            # Two certificates whose machine key is shared with a copy in the CurrentUser store of the test account. The copy
            # keeps the key reference, so it points at the same machine key, and the scan has to look across store locations.
            # One is removed from CurrentUser first, the other from LocalMachine first.
            $currentUserFirstCert = New-DbaComputerCertificate -SelfSigned
            $currentUserFirstKeyFile = & $getKeyFile $currentUserFirstCert.Thumbprint
            $localMachineFirstCert = New-DbaComputerCertificate -SelfSigned
            $localMachineFirstKeyFile = & $getKeyFile $localMachineFirstCert.Thumbprint
            $currentUserMy = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "My", "CurrentUser"
            $currentUserMy.Open("ReadWrite")
            $currentUserMy.Add((Get-ChildItem -Path "Cert:\LocalMachine\My\$($currentUserFirstCert.Thumbprint)"))
            $currentUserMy.Add((Get-ChildItem -Path "Cert:\LocalMachine\My\$($localMachineFirstCert.Thumbprint)"))
            $currentUserMy.Close()

            # A legacy CSP key container can hold a key exchange key and a signature key, and it can only be deleted as a whole.
            # A second certificate on the signature key in the container of the first certificate has to keep the container alive.
            # The provider is the Enhanced RSA and AES provider (type 24), because the SChannel provider of
            # New-DbaComputerCertificate creates no signature keys. Both keys are created in one container, then certreq
            # builds a self-signed certificate on each of them.
            $sharedContainer = "dbatoolsci_sharedcontainer_$(Get-Random)"
            $sharedProvider = "Microsoft Enhanced RSA and AES Cryptographic Provider"
            foreach ($keyNumber in 1, 2) {
                $containerKeyParameters = New-Object System.Security.Cryptography.CspParameters -ArgumentList 24, $sharedProvider, $sharedContainer
                $containerKeyParameters.KeyNumber = $keyNumber
                $containerKeyParameters.Flags = [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
                $containerKey = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList 2048, $containerKeyParameters
                $containerKey.Dispose()
            }
            $sharedRequestFiles = @()
            foreach ($keyName in "exchange", "signature") {
                $keySpec = if ($keyName -eq "exchange") { 1 } else { 2 }
                $sharedRequest = "$env:TEMP\dbatoolsci_$keyName.inf"
                $sharedRequestFiles += $sharedRequest, "$env:TEMP\dbatoolsci_$keyName.csr"
                $sharedRequestLines = @(
                    "[Version]",
                    "Signature=`"`$Windows NT`$`"",
                    "[NewRequest]",
                    "Subject = `"CN=dbatoolsci_$keyName`"",
                    "KeyContainer = `"$sharedContainer`"",
                    "UseExistingKeySet = TRUE",
                    "KeySpec = $keySpec",
                    "MachineKeySet = TRUE",
                    "Exportable = TRUE",
                    "FriendlyName = `"dbatoolsci_$keyName`"",
                    "ProviderName = `"$sharedProvider`"",
                    "ProviderType = 24",
                    "RequestType = Cert"
                )
                Set-Content -Path $sharedRequest -Value $sharedRequestLines
                $null = certreq -new -q $sharedRequest "$env:TEMP\dbatoolsci_$keyName.csr"
            }
            $exchangeCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object FriendlyName -eq "dbatoolsci_exchange"
            $signatureCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object FriendlyName -eq "dbatoolsci_signature"
            if (-not $exchangeCert -or -not $signatureCert) {
                throw "certreq did not create the two certificates on the shared container"
            }
            $exchangeKeyFile = & $getKeyFile $exchangeCert.Thumbprint

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # The deny rule is removed here as well, in case the test that sets it did not get to its finally block.
            & $setUnreadableFolderDenyRule -Present $false
            # A thumbprint is missing when the setup of its certificate failed, the cleanup goes on with the others.
            $leftovers = @($keptCert.Thumbprint, $cspCert.Thumbprint, $kspThumbprint, $sharedCert.Thumbprint, $webHostingCert.Thumbprint, $unreadableCert.Thumbprint, $currentUserFirstCert.Thumbprint, $localMachineFirstCert.Thumbprint, $exchangeCert.Thumbprint, $signatureCert.Thumbprint) | Where-Object { $PSItem }
            foreach ($leftover in $leftovers) {
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder TrustedPeople -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder WebHosting -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder $unreadableFolder -DeleteKey -WarningAction SilentlyContinue
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Store CurrentUser -DeleteKey -WarningAction SilentlyContinue
                # certreq puts a copy of a self-signed certificate into the intermediate CA store as well.
                $null = Remove-DbaComputerCertificate -Thumbprint $leftover -Folder CA -WarningAction SilentlyContinue
            }
            foreach ($requestFile in $sharedRequestFiles) {
                if (Test-Path -Path $requestFile) {
                    [System.IO.File]::Delete($requestFile)
                }
            }
            foreach ($keyFile in $keptKeyFile, $cspKeyFile, $kspKeyFile, $sharedKeyFile, $webHostingKeyFile, $unreadableKeyFile, $currentUserFirstKeyFile, $localMachineFirstKeyFile, $exchangeKeyFile) {
                if (Test-Path -Path $keyFile -PathType Leaf) {
                    [System.IO.File]::Delete($keyFile)
                }
            }
            if (-not $webHostingExisted) {
                # The test created the WebHosting folder, so its registry key goes again.
                [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\SystemCertificates", $true).DeleteSubKeyTree("WebHosting", $false)
            }
            # The custom folder is always created by the test, so its registry key goes as well.
            [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\SystemCertificates", $true).DeleteSubKeyTree($unreadableFolder, $false)
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

        It "Keeps a key when a folder of the store location cannot be read" {
            & $setUnreadableFolderDenyRule -Present $true
            try {
                # The folder is listed, but not readable, so the store open throws instead of showing the copy.
                (Get-ChildItem -Path "Cert:\LocalMachine").Name | Should -Contain $unreadableFolder
                { Get-ChildItem -Path "Cert:\LocalMachine\$unreadableFolder" -ErrorAction Stop } | Should -Throw

                $result = Remove-DbaComputerCertificate -Thumbprint $unreadableCert.Thumbprint -DeleteKey
                $result.Status | Should -Be "Removed"
                $result.PrivateKey | Should -Be "Not deleted: Cert:\LocalMachine\$unreadableFolder could not be read, so it is unknown whether another certificate uses the key"
                Test-Path -Path $unreadableKeyFile -PathType Leaf | Should -BeTrue
            } finally {
                & $setUnreadableFolderDenyRule -Present $false
            }

            # With the folder readable again, the copy in it still has a working key and takes the key with it.
            $lastResult = Remove-DbaComputerCertificate -Thumbprint $unreadableCert.Thumbprint -Folder $unreadableFolder -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $unreadableKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Keeps a machine key that a copy of the certificate in the other store location still uses" {
            # The copy in CurrentUser\My points at the machine key of the LocalMachine certificate.
            $userCopy = Get-ChildItem -Path "Cert:\CurrentUser\My\$($currentUserFirstCert.Thumbprint)"
            $userCopy.HasPrivateKey | Should -BeTrue
            [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($userCopy).Key.IsMachineKey | Should -BeTrue

            # Removed from CurrentUser first: the LocalMachine certificate still needs the key.
            $result = Remove-DbaComputerCertificate -Thumbprint $currentUserFirstCert.Thumbprint -Store CurrentUser -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Kept, shared with $($currentUserFirstCert.Thumbprint) in Cert:\LocalMachine\My"
            Test-Path -Path $currentUserFirstKeyFile -PathType Leaf | Should -BeTrue
            { [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey((Get-ChildItem -Path "Cert:\LocalMachine\My\$($currentUserFirstCert.Thumbprint)")) } | Should -Not -Throw

            $lastResult = Remove-DbaComputerCertificate -Thumbprint $currentUserFirstCert.Thumbprint -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $currentUserFirstKeyFile -PathType Leaf | Should -BeFalse

            # Removed from LocalMachine first: the copy in CurrentUser still needs the key.
            $result = Remove-DbaComputerCertificate -Thumbprint $localMachineFirstCert.Thumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Kept, shared with $($localMachineFirstCert.Thumbprint) in Cert:\CurrentUser\My"
            Test-Path -Path $localMachineFirstKeyFile -PathType Leaf | Should -BeTrue
            { [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey((Get-ChildItem -Path "Cert:\CurrentUser\My\$($localMachineFirstCert.Thumbprint)")) } | Should -Not -Throw

            $lastResult = Remove-DbaComputerCertificate -Thumbprint $localMachineFirstCert.Thumbprint -Store CurrentUser -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $localMachineFirstKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Keeps a legacy key container that still holds the key of another certificate and deletes it with the last one" {
            # The two certificates have different keys, but the keys share one container, which can only go as a whole.
            $result = Remove-DbaComputerCertificate -Thumbprint $exchangeCert.Thumbprint -DeleteKey
            $result.Status | Should -Be "Removed"
            $result.PrivateKey | Should -Be "Kept, key container shared with $($signatureCert.Thumbprint) in Cert:\LocalMachine\My"
            Test-Path -Path $exchangeKeyFile -PathType Leaf | Should -BeTrue
            { [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey((Get-ChildItem -Path "Cert:\LocalMachine\My\$($signatureCert.Thumbprint)")) } | Should -Not -Throw

            # Nothing uses the key exchange key any more, so the container goes with the last certificate.
            $lastResult = Remove-DbaComputerCertificate -Thumbprint $signatureCert.Thumbprint -DeleteKey
            $lastResult.Status | Should -Be "Removed"
            $lastResult.PrivateKey | Should -Be "Deleted"
            Test-Path -Path $exchangeKeyFile -PathType Leaf | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}