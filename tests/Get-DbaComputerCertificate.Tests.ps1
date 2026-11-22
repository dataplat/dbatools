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

Describe $CommandName -Tag IntegrationTests {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)
    # That was -Path, which called Import(). It uses the constructor now, so the tests run on pwsh as well.

    Context "Can get a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"

            # Get all certificates once for testing
            $allCertificates = Get-DbaComputerCertificate
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

    Context "Friendly name" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $friendlyName = "dbatoolsci_friendly_$(Get-Random)"
            $friendlyCertificate = New-DbaComputerCertificate -SelfSigned -FriendlyName $friendlyName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # DeleteKey, because New-DbaComputerCertificate created a private key in MachineKeys as well.
            $null = Remove-DbaComputerCertificate -Thumbprint $friendlyCertificate.Thumbprint -DeleteKey -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns the friendly name as Name and as FriendlyName" {
            # For a remote computer the FriendlyName arrives empty from the remoting serializer and the command
            # restores it from Name; on this local run both come straight from the store. The remote path has
            # no boundary in CI, so it was verified in the lab against a second computer, on both PowerShell editions.
            $result = Get-DbaComputerCertificate -Thumbprint $friendlyCertificate.Thumbprint
            $result.Name | Should -Be $friendlyName
            $result.FriendlyName | Should -Be $friendlyName
        }
    }

    Context "Certificate file" {
        It "reads a certificate file without a private key" {
            # -Path called Import() on the certificate object, which throws "X509Certificate is immutable on this platform" in
            # PowerShell 7.
            $result = Get-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt" -EnableException
            $result.Thumbprint | Should -Be "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $result.HasPrivateKey | Should -Be $false
            $result.PSObject.Properties.Name | Should -Not -Contain "HasKey"
        }
    }

    Context "Certificates on the computer of the instance" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For another computer the command runs in a WinRM session there, and the serializer rebuilds each certificate on
            # this side from its raw data. HasPrivateKey belongs to the store entry, so it arrived as False also when the key
            # was there, and Type did not reach the session, so it returned every certificate. On CI the instance is local, so
            # the session only happens against a lab whose instance runs on another computer.
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $keyFriendlyName = "dbatoolsci_key_$(Get-Random)"
            $keyCertificate = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned -FriendlyName $keyFriendlyName

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
            if ($keyCertificate) {
                $null = Invoke-Command2 -ComputerName $computerName -ScriptBlock $removeCertificateAndKey -ArgumentList $keyCertificate.Thumbprint
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reports the private key of the certificate" {
            $result = Get-DbaComputerCertificate -ComputerName $computerName -Thumbprint $keyCertificate.Thumbprint
            @($result).Count | Should -Be 1
            $result.HasPrivateKey | Should -Be $true
            $result.FriendlyName | Should -Be $keyFriendlyName
            $result.PSObject.Properties.Name | Should -Not -Contain "HasKey"
            $result.PSObject.Properties.Name | Should -Not -Contain "EkuList"
            @($result | Where-Object HasPrivateKey).Count | Should -Be 1
            # New-DbaComputerCertificate returns the certificate of a remote computer through Get-DbaComputerCertificate.
            $keyCertificate.HasPrivateKey | Should -Be $true
            $WarnVar | Should -BeNullOrEmpty
        }

        It "returns only certificates for server authentication by default" {
            # The Root folder holds certification authorities without Server Authentication, so the filter has something to drop.
            # The store adds the usages of most of them, they are not in the certificate, so this also checks that
            # EnhancedKeyUsageList shows the usages the filter saw.
            $allRoot = @(Get-DbaComputerCertificate -ComputerName $computerName -Folder Root -Type All)
            $serviceRoot = @(Get-DbaComputerCertificate -ComputerName $computerName -Folder Root)
            $serviceRoot.Count | Should -BeLessThan $allRoot.Count
            foreach ($rootCert in $serviceRoot) {
                "$($rootCert.EnhancedKeyUsageList)" | Should -Match "1\.3\.6\.1\.5\.5\.7\.3\.1"
            }
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}