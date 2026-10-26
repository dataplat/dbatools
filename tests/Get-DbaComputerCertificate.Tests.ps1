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

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)

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

            $null = Remove-DbaComputerCertificate -Thumbprint $friendlyCertificate.Thumbprint -ErrorAction SilentlyContinue

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
}