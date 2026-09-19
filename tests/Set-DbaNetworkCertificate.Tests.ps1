#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaNetworkCertificate",
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
                "Certificate",
                "Thumbprint",
                "UnsetCertificate",
                "Force",
                "RestartService",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceRestart -Property ComputerName
        $script:createdNetworkCertificateThumbprints = @()
        $null = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $test = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        foreach ($cert in $test.SuitableCertificates) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $cert.Thumbprint
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $test = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        foreach ($cert in $test.SuitableCertificates) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $cert.Thumbprint
        }
        foreach ($thumbprint in $script:createdNetworkCertificateThumbprints) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $thumbprint
        }
        Remove-Variable -Name createdNetworkCertificateThumbprints -Scope Script -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    It "Warns that no suitable certificate was found" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $WarnVar | Should -Match "No suitable certificate found"
    }

    It "Configures a certificate with a Key Storage Provider key and SQL Server loads it" {
        # New-SelfSignedCertificate creates a Key Storage Provider (CNG) key by default. SQL Server loads such a key
        # (verified with SQL Server 2019, 2022 and 2025), so the certificate counts as suitable and needs no -Force.
        # Its key file lives under Crypto\Keys instead of RSA\MachineKeys, and the read permission for the service SID
        # has to be granted there, otherwise the service does not start with this certificate.
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
        $vsName = (Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceRestart -OutputType Certificate -EnableException).VSName
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
        $script:createdNetworkCertificateThumbprints += $kspThumbprint

        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $kspThumbprint -RestartService
        $result.CertificateThumbprint | Should -Be $kspThumbprint
        $WarnVar | Should -BeNullOrEmpty

        # The proof that SQL Server accepted the key is the ERRORLOG line of the restart that names the thumbprint.
        $loadedCertificate = Get-DbaErrorLog -SqlInstance $TestConfig.InstanceRestart -LogNumber 0 -Text "successfully loaded for encryption"
        ($loadedCertificate.Text -join " ") | Should -Match $kspThumbprint
    }

    It "applies an unsuitable certificate when Force is used" {
        $splatNewUnsuitableCertificate = @{
            ComputerName           = $computerName
            SelfSigned             = $true
            DocumentEncryptionCert = $true
            EnableException        = $true
        }
        $unsuitableCertificate = New-DbaComputerCertificate @splatNewUnsuitableCertificate
        $script:createdNetworkCertificateThumbprints += $unsuitableCertificate.Thumbprint
        $suitability = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $unsuitableCertificate.Thumbprint -EnableException
        $suitability.EnhancedKeyUsageValid | Should -BeFalse

        # Forcing an unsuitable certificate warns about the failed checks, and not restarting the
        # service warns that the certificate is not in effect yet. Both are expected, so they are
        # silenced here because a test run must not print warnings. They are not asserted on $WarnVar:
        # this call runs with EnableException, and then the warnings do not reach the warning variable.
        $splatSetUnsuitableCertificate = @{
            SqlInstance     = $TestConfig.InstanceRestart
            Thumbprint      = $unsuitableCertificate.Thumbprint
            Force           = $true
            Confirm         = $false
            EnableException = $true
            WarningAction   = "SilentlyContinue"
        }
        $result = Set-DbaNetworkCertificate @splatSetUnsuitableCertificate
        $configuredCertificate = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -EnableException

        $result.CertificateThumbprint | Should -Be $unsuitableCertificate.Thumbprint
        $configuredCertificate.ConfiguredCertificateThumbprint | Should -Be $unsuitableCertificate.Thumbprint
    }

    It "Creates a first self-signed certificate and applies it" {
        $result = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned | Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Creates a second self-signed certificate and applies it" {
        $result = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned | Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Does nothing if the certificate is already applied" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $result.Notes | Should -Be "No changes needed"
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Still finds the configured certificate after it has been archived" {
        # Auto-renewed certificates are archived as soon as the successor is issued, but SQL Server keeps using
        # them until it is reconfigured. Archived certificates are hidden from Get-ChildItem without -Force.
        $configuredThumbprint = (Get-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -EnableException).Thumbprint
        $configuredThumbprint | Should -Not -BeNullOrEmpty

        $setArchived = {
            param ($Thumbprint, $Archived)
            (Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint" -Force).Archived = $Archived
        }

        try {
            $splatArchive = @{
                ComputerName = $computerName
                ScriptBlock  = $setArchived
                ArgumentList = $configuredThumbprint, $true
            }
            $null = Invoke-Command2 @splatArchive

            $archivedCertificate = Get-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -EnableException
            $archivedCertificate.Thumbprint | Should -Be $configuredThumbprint

            $splatTestArchived = @{
                SqlInstance     = $TestConfig.InstanceRestart
                Thumbprint      = $configuredThumbprint
                EnableException = $true
            }
            $archivedSuitability = Test-DbaNetworkCertificate @splatTestArchived
            $archivedSuitability.CertificateFound | Should -BeTrue
        } finally {
            $splatUnarchive = @{
                ComputerName = $computerName
                ScriptBlock  = $setArchived
                ArgumentList = $configuredThumbprint, $false
            }
            $null = Invoke-Command2 @splatUnarchive
        }
    }

    It "Unsets the certificate" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $result.CertificateThumbprint | Should -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }
}
