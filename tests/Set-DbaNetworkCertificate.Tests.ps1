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

        $splatSetUnsuitableCertificate = @{
            SqlInstance     = $TestConfig.InstanceRestart
            Thumbprint      = $unsuitableCertificate.Thumbprint
            Force           = $true
            Confirm         = $false
            EnableException = $true
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

    It "Unsets the certificate" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $result.CertificateThumbprint | Should -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }
}
