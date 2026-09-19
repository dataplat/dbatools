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
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $certificate.Thumbprint, $kspThumbprint -EnableException
        }

        It "Should return a suitable certificate thumbprint" {
            $results.SuitableCertificate.Thumbprint | Should -Contain $certificate.Thumbprint
        }

        It "Should list a certificate with a Key Storage Provider key as suitable" {
            $results.SuitableCertificate.Thumbprint | Should -Contain $kspThumbprint
        }
    }
}