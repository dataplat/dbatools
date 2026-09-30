#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "Provider",
                "Store",
                "Folder",
                "Flag",
                "Dns",
                "SelfSigned",
                "DocumentEncryptionCert",
                "EnableException",
                "HashAlgorithm",
                "MonthsValid"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "DocumentEncryptionCert validation" {
            BeforeAll {
                Mock Stop-Function { throw $Message }
            }

            It "requires SelfSigned or an explicit certificate template" {
                {
                    New-DbaComputerCertificate -DocumentEncryptionCert
                } | Should -Throw "*requires -SelfSigned or an explicit -CertificateTemplate*"
            }
        }
    }

    Context "NonExportable handling" {
        BeforeAll {
            $script:remoteFqdn = "dbatools-review-remote.example"
            $script:requestConfig = @()

            Mock Get-DbaCmObject -ModuleName "dbatools" {
                [pscustomobject]@{
                    OSLanguage = 1033
                }
            }
            Mock Resolve-DbaNetworkName -ModuleName "dbatools" {
                [pscustomobject]@{
                    Fqdn = $script:remoteFqdn
                }
            }
            Mock Test-ElevationRequirement -ModuleName "dbatools" { $true }
            Mock Set-Content -ModuleName "dbatools" {
                param($Path, $Value)
                $script:requestConfig = @($Value)
            }
            Mock Add-Content -ModuleName "dbatools" {
                param($Path, $Value)
                $script:requestConfig += $Value
            }
        }

        It "Keeps the source certificate exportable for remote installs when NonExportable is requested" {
            $splatRemoteCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                Flag         = "NonExportable"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatRemoteCertificate

            $script:requestConfig | Should -Contain "Exportable = TRUE"
            $script:requestConfig | Should -Not -Contain "Exportable = FALSE"
        }

        It "Writes a Key Storage Provider request when Provider asks for one" {
            $splatKspCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                Provider     = "Microsoft Software Key Storage Provider"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatKspCertificate

            $script:requestConfig | Should -Contain "ProviderName = ""Microsoft Software Key Storage Provider"""
            $script:requestConfig | Should -Contain "KeyAlgorithm = RSA"
            $script:requestConfig | Should -Not -Contain "KeySpec = 1"
            $script:requestConfig | Should -Not -Contain "ProviderType = 12"
        }

        It "Writes a legacy CSP request with KeySpec AT_KEYEXCHANGE by default" {
            $splatDefaultCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatDefaultCertificate

            $script:requestConfig | Should -Contain "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
            $script:requestConfig | Should -Contain "ProviderType = 12"
            $script:requestConfig | Should -Contain "KeySpec = 1"
            $script:requestConfig | Should -Not -Contain "KeyAlgorithm = RSA"
        }
    }
}

# These tests used to be skipped when APPVEYOR is set, which the Azure lanes do as well. Creating a self-signed
# certificate in LocalMachine\My works on the runners, so they run there now.
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # The thumbprints of the requests in LocalMachine\REQUEST whose public key is in one of the given request files.
        # Every request has its own key, so this names exactly the requests of those files and nothing that another
        # enrollment on this computer created in the meantime.
        function Get-TestRequestThumbprint {
            param ([string[]]$RequestFile)
            foreach ($file in $RequestFile) {
                if (-not (Test-Path -Path $file)) {
                    continue
                }
                $requestBase64 = (Get-Content -Path $file | Where-Object { $PSItem -notmatch "^-----" }) -join ""
                $requestHex = [System.BitConverter]::ToString([System.Convert]::FromBase64String($requestBase64))
                Get-ChildItem -Path Cert:\LocalMachine\REQUEST | Where-Object { $requestHex.Contains([System.BitConverter]::ToString($PSItem.PublicKey.EncodedKeyValue.RawData)) } | ForEach-Object { $PSItem.Thumbprint }
            }
        }
    }

    Context "Can generate a new certificate with default settings" {
        BeforeAll {
            $defaultCert = New-DbaComputerCertificate -SelfSigned -EnableException
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

        It "Leaves no copy of the certificate in the intermediate CA store" {
            # certreq installs a self-signed certificate a second time, without its key, in LocalMachine\CA. The command removes that copy.
            Test-Path -Path "Cert:\LocalMachine\My\$($defaultCert.Thumbprint)" | Should -BeTrue
            Test-Path -Path "Cert:\LocalMachine\CA\$($defaultCert.Thumbprint)" | Should -BeFalse
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

    Context "Can generate a document encryption certificate for Always Encrypted" {
        BeforeAll {
            $documentCert = New-DbaComputerCertificate -SelfSigned -DocumentEncryptionCert -EnableException
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $documentCert.Thumbprint
        }

        It "Returns the Document Encryption EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.4\.1\.311\.10\.3\.11" | Should -BeTrue
        }

        It "Returns the IKE Intermediate EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.8\.2\.2" | Should -BeTrue
        }

        It "Does not include the Server Authentication EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.7\.3\.1" | Should -BeFalse
        }
    }

    Context "Can generate a certificate with a Key Storage Provider key" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command returns a copy of the certificate object without the key, so the private key is read from the store entry.
            $kspCert = New-DbaComputerCertificate -SelfSigned -Provider "Microsoft Software Key Storage Provider"
            $kspStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($kspCert.Thumbprint)"
            $kspKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($kspStoreCert)

            $cspCert = New-DbaComputerCertificate -SelfSigned
            $cspStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($cspCert.Thumbprint)"
            $cspKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cspStoreCert)

            # For a remote computer the command exports a PFX and imports it on the target. The provider has to survive that transfer.
            # On CI the instance is local, so the transfer only happens against a lab whose instance runs on another computer.
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $remoteIsLocal = ([DbaInstanceParameter]$TestConfig.InstanceSingle).IsLocalHost
            # The key files of this computer before the certificate for the other computer is created here. After the export
            # the certificate and its key have to be gone from this computer again.
            $keyFolders = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys", "$env:ProgramData\Microsoft\Crypto\Keys"
            $keyFilesBefore = @((Get-ChildItem -Path $keyFolders -File).Name)
            $remoteKspCert = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned -Provider "Microsoft Software Key Storage Provider"
            $keyFilesAfter = @((Get-ChildItem -Path $keyFolders -File).Name)
            $readProvider = {
                param ($Thumbprint)
                $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint"
                ([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)).Key.Provider.Provider
            }
            $splatReadProvider = @{
                ComputerName = $computerName
                ScriptBlock  = $readProvider
                ArgumentList = $remoteKspCert.Thumbprint
                # Raw, because Invoke-Command2 otherwise wraps the string in an object that only has a Length.
                Raw          = $true
            }
            $remoteProvider = Invoke-Command2 @splatReadProvider

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaComputerCertificate -Thumbprint $kspCert.Thumbprint, $cspCert.Thumbprint
            Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $remoteKspCert.Thumbprint
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Holds the private key in the Key Storage Provider" {
            $kspKey.Key.Provider.Provider | Should -Be "Microsoft Software Key Storage Provider"
            Test-Path -Path "$env:ProgramData\Microsoft\Crypto\Keys\$($kspKey.Key.UniqueName)" -PathType Leaf | Should -BeTrue
        }

        It "Holds the private key in the legacy CSP with KeySpec AT_KEYEXCHANGE by default" {
            $cspKey.Key.Provider.Provider | Should -Be "Microsoft RSA SChannel Cryptographic Provider"
            # A legacy CSP key opened through CNG reports an AT_KEYEXCHANGE KeySpec as AllUsages, an AT_SIGNATURE one as Signing.
            $cspKey.Key.KeyUsage | Should -Be "AllUsages"
            Test-Path -Path "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$($cspKey.Key.UniqueName)" -PathType Leaf | Should -BeTrue
        }

        It "Keeps the Key Storage Provider key when the certificate is imported on a remote computer" {
            $remoteProvider | Should -Be "Microsoft Software Key Storage Provider"
        }

        It "Leaves neither the certificate nor its key on this computer after the transfer to a remote computer" {
            if ($remoteIsLocal) {
                Set-ItResult -Skipped -Because "the instance runs on this computer, so the certificate stays here"
            }
            Test-Path -Path "Cert:\LocalMachine\My\$($remoteKspCert.Thumbprint)" | Should -BeFalse
            Test-Path -Path "Cert:\LocalMachine\CA\$($remoteKspCert.Thumbprint)" | Should -BeFalse
            $keyFilesAfter | Where-Object { $PSItem -notin $keyFilesBefore } | Should -BeNullOrEmpty
        }
    }

    Context "Leaves nothing behind when the CA does not answer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Every request file certreq writes is copied, so that cleanup and assertions know the requests of this test by
            # their keys and never touch a request another enrollment on this computer created meanwhile. certreq is real.
            # No temp name in this file starts with dbatools: the maintenance task tempcleanup deletes everything in the temp
            # folder that does, one minute after the module is imported, which is right in the middle of this file.
            $global:dbatoolsciCsrCopyFolder = "$([System.IO.Path]::GetTempPath())csrcopy_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $global:dbatoolsciCsrCopyFolder -ItemType Directory
            $mockCertreq = {
                certreq.exe @args
                if ($args -contains "-new") {
                    Copy-Item -Path $args[-1] -Destination (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath "$(Get-Random).csr")
                }
            }
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            # A request for a CA waits in LocalMachine\REQUEST with its key. When the CA cannot be reached the command removes
            # the request again, so the store and the key folders have to look as before.
            $requestFolders = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys", "$env:ProgramData\Microsoft\Crypto\Keys"
            $requestKeyFilesBefore = @((Get-ChildItem -Path $requestFolders -File).Name)
            $splatUnreachableCa = @{
                CaServer        = "nosuchca.dbatools.invalid"
                CaName          = "NoSuchCA"
                WarningVariable = "unreachableCaWarning"
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            $unreachableCaResult = New-DbaComputerCertificate @splatUnreachableCa
            $requestFiles = @((Get-ChildItem -Path $global:dbatoolsciCsrCopyFolder -Filter "*.csr").FullName)
            $ownRequestsAfter = @(Get-TestRequestThumbprint -RequestFile $requestFiles)
            $requestKeyFilesAfter = @((Get-ChildItem -Path $requestFolders -File).Name)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # In case the command left its request behind after all. Only the requests of this test are removed.
            foreach ($leftover in (Get-TestRequestThumbprint -RequestFile $requestFiles)) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $global:dbatoolsciCsrCopyFolder -Recurse -ErrorAction SilentlyContinue
            Remove-Variable -Name dbatoolsciCsrCopyFolder -Scope Global -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns instead of returning a certificate" {
            $unreachableCaResult | Should -BeNullOrEmpty
            # The command writes several warnings on this path, the last one is the message of Stop-Function.
            ($unreachableCaWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Removes the pending request and its key again" {
            $requestFiles | Should -HaveCount 1
            $ownRequestsAfter | Should -BeNullOrEmpty
            $requestKeyFilesAfter | Where-Object { $PSItem -notin $requestKeyFilesBefore } | Should -BeNullOrEmpty
        }
    }

    Context "Keeps a request of someone else when the CA does not answer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Another enrollment creates its own machine request while the command waits for the CA. Only the submission is
            # intercepted to create that request at exactly this moment; certreq, the store and the keys are real.
            $otherSubject = "CN=dbatoolsci_otherrequest_$(Get-Random)"
            $global:dbatoolsciOtherInf = "$([System.IO.Path]::GetTempPath())otherrequest_dbatoolsci_$(Get-Random).inf"
            $otherCsr = "$global:dbatoolsciOtherInf.csr"
            $otherInfContent = @"
[Version]
Signature="`$Windows NT`$"
[NewRequest]
Subject = "$otherSubject"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
ProviderName = "Microsoft Software Key Storage Provider"
KeyAlgorithm = RSA
RequestType = PKCS10
"@
            Set-Content -Path $global:dbatoolsciOtherInf -Value $otherInfContent
            $global:dbatoolsciCsrCopyFolder = "$([System.IO.Path]::GetTempPath())csrcopy_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $global:dbatoolsciCsrCopyFolder -ItemType Directory
            $mockCertreq = {
                if ($args -contains "-submit") {
                    $null = certreq.exe -q -new $global:dbatoolsciOtherInf "$global:dbatoolsciOtherInf.csr"
                }
                certreq.exe @args
                if ($args -contains "-new") {
                    Copy-Item -Path $args[-1] -Destination (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath "$(Get-Random).csr")
                }
            }
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            $splatUnreachableCa = @{
                CaServer        = "nosuchca.dbatools.invalid"
                CaName          = "NoSuchCA"
                WarningVariable = "otherRequestWarning"
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            $otherRequestResult = New-DbaComputerCertificate @splatUnreachableCa
            $requestFiles = @((Get-ChildItem -Path $global:dbatoolsciCsrCopyFolder -Filter "*.csr").FullName)
            $ownRequestsAfter = @(Get-TestRequestThumbprint -RequestFile $requestFiles)
            $otherRequest = Get-ChildItem -Path Cert:\LocalMachine\REQUEST | Where-Object Thumbprint -in @(Get-TestRequestThumbprint -RequestFile $otherCsr)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # The requests of this test: the one of the command, should it still be there, and the other one.
            foreach ($leftover in (Get-TestRequestThumbprint -RequestFile ($requestFiles + $otherCsr))) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $global:dbatoolsciOtherInf, $otherCsr -ErrorAction SilentlyContinue
            Remove-Item -Path $global:dbatoolsciCsrCopyFolder -Recurse -ErrorAction SilentlyContinue
            Remove-Variable -Name dbatoolsciCsrCopyFolder, dbatoolsciOtherInf -Scope Global -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns instead of returning a certificate" {
            $otherRequestResult | Should -BeNullOrEmpty
            ($otherRequestWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Removes only its own request" {
            $requestFiles | Should -HaveCount 1
            $ownRequestsAfter | Should -BeNullOrEmpty
            $otherRequest | Should -Not -BeNullOrEmpty
        }

        It "Keeps the key of the other request" {
            $otherKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($otherRequest)
            $otherKey | Should -Not -BeNullOrEmpty
            # Signing needs the key file itself, the certificate only points to it.
            $otherKey.SignData([byte[]](1, 2, 3), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Removes only its own request when a second call for the same computer overlaps" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # While the first call waits for the CA, a second call for the same computer runs from start to end. Only the
            # submission of the first call is intercepted to start the second one at exactly this moment; both calls, certreq,
            # the store and the keys are real. The request files of both calls are copied to know their requests afterwards.
            # With one request folder per computer the second call deleted the request file of the first one, which then
            # could not find its own request and left it behind.
            $global:dbatoolsciCsrCopyFolder = "$([System.IO.Path]::GetTempPath())csrcopy_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $global:dbatoolsciCsrCopyFolder -ItemType Directory
            $global:dbatoolsciSecondCallStarted = $false
            $mockCertreq = {
                if ($args -contains "-submit" -and -not $global:dbatoolsciSecondCallStarted) {
                    $global:dbatoolsciSecondCallStarted = $true
                    $splatSecondCall = @{
                        CaServer        = "nosuchca.dbatools.invalid"
                        CaName          = "NoSuchCA"
                        WarningVariable = "secondCallWarning"
                        WarningAction   = "SilentlyContinue"
                        EnableException = $false
                    }
                    $global:dbatoolsciSecondCallResult = New-DbaComputerCertificate @splatSecondCall
                    $global:dbatoolsciSecondCallWarning = $secondCallWarning
                }
                certreq.exe @args
                if ($args -contains "-new") {
                    Copy-Item -Path $args[-1] -Destination (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath "$(Get-Random).csr")
                }
            }
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            $splatFirstCall = @{
                CaServer        = "nosuchca.dbatools.invalid"
                CaName          = "NoSuchCA"
                WarningVariable = "firstCallWarning"
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            $firstCallResult = New-DbaComputerCertificate @splatFirstCall
            $requestFiles = @((Get-ChildItem -Path $global:dbatoolsciCsrCopyFolder -Filter "*.csr").FullName)
            $ownRequestsAfter = @(Get-TestRequestThumbprint -RequestFile $requestFiles)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            foreach ($leftover in (Get-TestRequestThumbprint -RequestFile $requestFiles)) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $global:dbatoolsciCsrCopyFolder -Recurse -ErrorAction SilentlyContinue
            Remove-Variable -Name dbatoolsciCsrCopyFolder, dbatoolsciSecondCallStarted, dbatoolsciSecondCallResult, dbatoolsciSecondCallWarning -Scope Global -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Runs the second call while the first one waits" {
            $global:dbatoolsciSecondCallStarted | Should -BeTrue
            $requestFiles | Should -HaveCount 2
        }

        It "Warns in both calls instead of returning a certificate" {
            $firstCallResult | Should -BeNullOrEmpty
            $global:dbatoolsciSecondCallResult | Should -BeNullOrEmpty
            ($firstCallWarning -join " ") | Should -Match "Failure when attempting to create the cert"
            ($global:dbatoolsciSecondCallWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Leaves no request of either call behind" {
            $ownRequestsAfter | Should -BeNullOrEmpty
        }
    }

    # A real CA refuses a template it does not offer right away. Its message "Certificate not issued" contains "issued", which
    # the command once took for success: it then tried to install a certificate that was never written and left the request behind.
    # No CI environment has a CA, so this runs only against a lab that sets CaServer and CaName in its configuration.
    Context "Removes the request when the CA refuses it" -Skip:(-not $TestConfig.CaServer) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The request files are copied to know the request of this test by its key, see the contexts above. certreq is real.
            $global:dbatoolsciCsrCopyFolder = "$([System.IO.Path]::GetTempPath())csrcopy_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $global:dbatoolsciCsrCopyFolder -ItemType Directory
            $mockCertreq = {
                certreq.exe @args
                if ($args -contains "-new") {
                    Copy-Item -Path $args[-1] -Destination (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath "$(Get-Random).csr")
                }
            }
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            $splatRefusingCa = @{
                CaServer            = $TestConfig.CaServer
                CaName              = $TestConfig.CaName
                CertificateTemplate = "dbatoolsci_NoSuchTemplate"
                WarningVariable     = "refusedWarning"
                WarningAction       = "SilentlyContinue"
                EnableException     = $false
            }
            $refusedResult = New-DbaComputerCertificate @splatRefusingCa
            $requestFiles = @((Get-ChildItem -Path $global:dbatoolsciCsrCopyFolder -Filter "*.csr").FullName)
            $ownRequestsAfter = @(Get-TestRequestThumbprint -RequestFile $requestFiles)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            foreach ($leftover in (Get-TestRequestThumbprint -RequestFile $requestFiles)) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $global:dbatoolsciCsrCopyFolder -Recurse -ErrorAction SilentlyContinue
            Remove-Variable -Name dbatoolsciCsrCopyFolder -Scope Global -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns with the reason of the CA instead of returning a certificate" {
            $refusedResult | Should -BeNullOrEmpty
            ($refusedWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Removes its request and the key again" {
            $requestFiles | Should -HaveCount 1
            $ownRequestsAfter | Should -BeNullOrEmpty
        }
    }

    # A real CA whose template holds every request as pending until a CA manager approves it. No CI environment has one,
    # so this runs only against a lab that sets CaServer, CaName and ApprovalTemplate in its configuration.
    Context "Keeps a pending request so that the certificate can be installed once it is issued" -Skip:(-not $TestConfig.ApprovalTemplate) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The request files are copied to know the request of this test by its key, see the contexts above. certreq is real.
            $global:dbatoolsciCsrCopyFolder = "$([System.IO.Path]::GetTempPath())csrcopy_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $global:dbatoolsciCsrCopyFolder -ItemType Directory
            $mockCertreq = {
                certreq.exe @args
                if ($args -contains "-new") {
                    Copy-Item -Path $args[-1] -Destination (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath "$(Get-Random).csr")
                }
            }
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            $caConfig = "$($TestConfig.CaServer)\$($TestConfig.CaName)"
            $splatPendingCa = @{
                CaServer            = $TestConfig.CaServer
                CaName              = $TestConfig.CaName
                CertificateTemplate = $TestConfig.ApprovalTemplate
                WarningVariable     = "pendingWarning"
                WarningAction       = "SilentlyContinue"
                EnableException     = $false
            }
            $pendingResult = New-DbaComputerCertificate @splatPendingCa
            $requestFiles = @((Get-ChildItem -Path $global:dbatoolsciCsrCopyFolder -Filter "*.csr").FullName)
            $pendingRequest = Get-ChildItem -Path Cert:\LocalMachine\REQUEST | Where-Object Thumbprint -in @(Get-TestRequestThumbprint -RequestFile $requestFiles)
            $pendingRequestId = ([regex]::Match("$pendingWarning", "certificate request (\d+)")).Groups[1].Value

            # A CA manager approves the request, then the certreq commands the warning names install the certificate. They
            # run with -q here, so that a failure reports instead of showing a dialog.
            $approval = certutil -config $caConfig -resubmit $pendingRequestId
            $retrieveCommand = [regex]::Match("$pendingWarning", "certreq -retrieve -config `"([^`"]+)`" (\d+) (\S+\.crt)")
            $acceptCommand = [regex]::Match("$pendingWarning", "certreq -accept -machine (\S+\.crt)")
            $issuedCrt = Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath $retrieveCommand.Groups[3].Value
            $null = certreq.exe -q -retrieve -config $retrieveCommand.Groups[1].Value $retrieveCommand.Groups[2].Value $issuedCrt
            $null = certreq.exe -q -accept -machine (Join-Path -Path $global:dbatoolsciCsrCopyFolder -ChildPath $acceptCommand.Groups[1].Value)
            $issuedThumbprint = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $issuedCrt).Thumbprint
            $installedCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object Thumbprint -eq $issuedThumbprint
            $requestAfterAccept = @(Get-TestRequestThumbprint -RequestFile $requestFiles)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            if ($issuedThumbprint -and (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object Thumbprint -eq $issuedThumbprint)) {
                Remove-DbaComputerCertificate -Thumbprint $issuedThumbprint -DeleteKey
            }
            foreach ($leftover in (Get-TestRequestThumbprint -RequestFile $requestFiles)) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $global:dbatoolsciCsrCopyFolder -Recurse -ErrorAction SilentlyContinue
            Remove-Variable -Name dbatoolsciCsrCopyFolder -Scope Global -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns with the request ID instead of returning a certificate" {
            $pendingResult | Should -BeNullOrEmpty
            ($pendingWarning -join " ") | Should -Match "as pending"
            $pendingRequestId | Should -Match "^\d+$"
        }

        It "Keeps the request and its key while the CA holds it" {
            $requestFiles | Should -HaveCount 1
            $pendingRequest | Should -HaveCount 1
            $pendingKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($pendingRequest)
            # Signing needs the key file itself, the certificate only points to it.
            $pendingKey.SignData([byte[]](1, 2, 3), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -Not -BeNullOrEmpty
        }

        It "Installs the certificate with its private key once a CA manager has approved it" {
            "$approval" | Should -Match "-resubmit command completed successfully"
            $retrieveCommand.Groups[1].Value | Should -Be $caConfig
            $retrieveCommand.Groups[2].Value | Should -Be $pendingRequestId
            $acceptCommand.Groups[1].Value | Should -Be $retrieveCommand.Groups[3].Value
            $installedCert | Should -Not -BeNullOrEmpty
            $installedCert.HasPrivateKey | Should -BeTrue
            $requestAfterAccept | Should -BeNullOrEmpty
        }
    }
}
