#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
                "RestartService",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceRestart -Property ComputerName
        $test = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        if ($test.ConfiguredCertificateThumbprint) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $test.ConfiguredCertificateThumbprint
        }
    }

    It "Warns that no suitable certificate was found" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $WarnVar | Should -Match "No suitable certificate found"
    }

    It "Creates a self-signed certificate and applies it" {
        $result = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned | Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService
        $result | Should -Not -BeNullOrEmpty
    }

    It "Does nothing if the certificate is already applied" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        $result.Notes | Should -Be "No changes needed"
    }
}