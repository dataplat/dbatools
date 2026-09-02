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

    It "Says why a certificate with a CNG key is unsuitable" {
        # New-SelfSignedCertificate creates a Key Storage Provider (CNG) key by default. SQL Server cannot use
        # such a key, and the refusal has to name that reason instead of a bare PrivateKeyInvalid.
        $newCngCertificate = {
            param ($DnsName)
            $splatCertificate = @{
                DnsName           = $DnsName
                CertStoreLocation = "Cert:\LocalMachine\My"
                FriendlyName      = "dbatoolsci_cng_key"
            }
            (New-SelfSignedCertificate @splatCertificate).Thumbprint
        }
        $splatCreateCng = @{
            ComputerName = $computerName
            ScriptBlock  = $newCngCertificate
            ArgumentList = $computerName
            # Raw, because Invoke-Command2 otherwise wraps the string in an object that only has a Length.
            Raw          = $true
        }
        $cngThumbprint = Invoke-Command2 @splatCreateCng
        $script:createdNetworkCertificateThumbprints += $cngThumbprint

        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $cngThumbprint -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $WarnVar | Should -Match "PrivateKeyInvalid"
        $WarnVar | Should -Match "legacy CSP key with KeySpec AT_KEYEXCHANGE"
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
