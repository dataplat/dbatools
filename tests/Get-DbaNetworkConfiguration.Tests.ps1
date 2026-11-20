#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaNetworkConfiguration",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "OutputType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpProperties
        }

        It "Should Return a Result" {
            $resultsFull | Should -Not -Be $null
            $resultsTcpIpProperties | Should -Not -Be $null
        }

        It "has the correct properties" {
            $expectedPropsFull = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SharedMemoryEnabled",
                "NamedPipesEnabled",
                "TcpIpEnabled",
                "TcpIpProperties",
                "TcpIpAddresses",
                "Certificate",
                "SuitableCertificate",
                "Advanced"
            )
            ($resultsFull.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsFull | Sort-Object)

            $expectedPropsTcpIpProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Enabled",
                "KeepAlive",
                "ListenAll"
            )
            ($resultsTcpIpProperties.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsTcpIpProperties | Sort-Object)
        }
    }

    Context "Command returns correct certificate information" {
        BeforeAll {
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName

            # On a failover cluster instance the certificate must carry the virtual network name of the
            # instance, but New-DbaComputerCertificate resolves that name to the node it currently runs
            # on and would issue the certificate for the node. So read the virtual server name first and
            # pass it as ClusterInstanceName, which is the documented way to certify a cluster instance.
            # On a stand-alone instance VSName is empty and the certificate is issued for the node.
            $vsName = (Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType Certificate -EnableException).VSName
            $splatCertificate = @{
                ComputerName    = $computerName
                SelfSigned      = $true
                KeyLength       = 2048
                HashAlgorithm   = "Sha256"
                FriendlyName    = "dbatoolsci_csp_key"
                EnableException = $true
            }
            if ($vsName) {
                $splatCertificate.ClusterInstanceName = $vsName
            }
            $certificate = New-DbaComputerCertificate @splatCertificate

            # New-SelfSignedCertificate creates a Key Storage Provider (CNG) key by default. SQL Server loads such a
            # key, so the certificate has to be listed as suitable next to the legacy CSP one from New-DbaComputerCertificate.
            $newSelfSignedCertificate = {
                param ($Options)
                $networkName = if ($Options.VsName) { $Options.VsName } else { hostname }
                $dnsName = @()
                try {
                    $dnsName += [System.Net.Dns]::GetHostEntry($networkName).HostName
                } catch {
                    # Without a DNS entry the short name alone satisfies the DNS name check.
                }
                $dnsName += $networkName
                $splatCertificate = @{
                    DnsName           = $dnsName | Select-Object -Unique
                    CertStoreLocation = "Cert:\LocalMachine\My"
                    FriendlyName      = $Options.FriendlyName
                    KeyAlgorithm      = "RSA"
                    KeyLength         = 2048
                    HashAlgorithm     = "SHA256"
                    KeyUsage          = "DigitalSignature", "KeyEncipherment"
                    TextExtension     = @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")
                    Provider          = $Options.Provider
                }
                (New-SelfSignedCertificate @splatCertificate).Thumbprint
            }
            $kspOptions = @{
                FriendlyName = "dbatoolsci_ksp_key"
                VsName       = $vsName
                Provider     = "Microsoft Software Key Storage Provider"
            }
            $splatCreateKsp = @{
                ComputerName = $computerName
                ScriptBlock  = $newSelfSignedCertificate
                ArgumentList = $kspOptions
                # Raw, because Invoke-Command2 otherwise wraps the string in an object that only has a Length.
                Raw          = $true
            }
            $kspThumbprint = Invoke-Command2 @splatCreateKsp

            $results = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        AfterAll {
            # The keys go as well. Remove-DbaComputerCertificate -DeleteKey keeps the key on a remote computer, because the WinRM
            # session cannot open CurrentUser\UserDS (#10823), so the certificates and their key files are removed here.
            $removeCertificateAndKey = {
                param ([string[]]$Thumbprint)
                foreach ($certThumbprint in $Thumbprint) {
                    $storeCert = Get-Item -Path "Cert:\LocalMachine\My\$certThumbprint" -ErrorAction SilentlyContinue
                    if ($storeCert) {
                        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($storeCert)
                        Remove-Item -Path "Cert:\LocalMachine\My\$certThumbprint"
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
            }
            $splatRemoveCertificates = @{
                ComputerName = $computerName
                ScriptBlock  = $removeCertificateAndKey
                ArgumentList = (, [string[]]($certificate.Thumbprint, $kspThumbprint))
            }
            $null = Invoke-Command2 @splatRemoveCertificates
        }

        It "Should return a suitable certificate thumbprint" {
            $results.SuitableCertificate.Thumbprint | Should -Contain $certificate.Thumbprint
        }

        It "Should list a certificate with a Key Storage Provider key as suitable" {
            $results.SuitableCertificate.Thumbprint | Should -Contain $kspThumbprint
        }

        It "Should report the private key and the friendly name of the suitable certificates" {
            # For another computer the scriptblock runs in a WinRM session, and the serializer rebuilds each certificate on this
            # side from its raw data: HasPrivateKey arrived as False and FriendlyName empty, although suitability needs the key.
            # On CI the instance is local, so the session only happens against a lab whose instance runs on another computer.
            $cspResult = $results.SuitableCertificate | Where-Object Thumbprint -eq $certificate.Thumbprint
            $cspResult.HasPrivateKey | Should -Be $true
            $cspResult.FriendlyName | Should -Be "dbatoolsci_csp_key"
            $kspResult = $results.SuitableCertificate | Where-Object Thumbprint -eq $kspThumbprint
            $kspResult.HasPrivateKey | Should -Be $true
            $kspResult.FriendlyName | Should -Be "dbatoolsci_ksp_key"
            @($results.SuitableCertificate | Where-Object HasPrivateKey).Count | Should -Be @($results.SuitableCertificate).Count
            $results.SuitableCertificate[0].PSObject.Properties.Name | Should -Not -Contain "HasKey"
            $results.SuitableCertificate[0].PSObject.Properties.Name | Should -Not -Contain "FriendlyNameValue"
        }
    }
}