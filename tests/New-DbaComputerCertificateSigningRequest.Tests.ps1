#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaComputerCertificateSigningRequest",
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
                "ClusterInstanceName",
                "Path",
                "FriendlyName",
                "KeyLength",
                "Dns",
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

        $requestPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $requestPath -ItemType Directory
        $requestFriendlyName = "dbatoolsci_csr_$(Get-Random)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # certreq -new leaves the pending request with its private key in the REQUEST store of the local machine.
        $requestStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("REQUEST", "LocalMachine")
        $requestStore.Open("ReadWrite")
        foreach ($pendingRequest in ($requestStore.Certificates | Where-Object FriendlyName -eq $requestFriendlyName)) {
            $requestStore.Remove($pendingRequest)
        }
        $requestStore.Close()
        if (Test-Path -Path $requestPath) {
            [System.IO.Directory]::Delete($requestPath, $true)
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Generates a configuration file and a signing request with a 2048 bit key" {
        $files = New-DbaComputerCertificateSigningRequest -Path $requestPath -FriendlyName $requestFriendlyName
        $files.Count | Should -Be 2
        $files.Name | Should -Contain "request.inf"
        $signingRequest = $files | Where-Object Extension -eq ".csr"
        $signingRequest | Should -Not -BeNullOrEmpty
        # certutil reads the request; the key length is the property of the key that a certificate issued from it inherits.
        (certutil -dump $signingRequest.FullName) -join " " | Should -Match "Public Key Length: 2048 bits"
        $WarnVar | Should -BeNullOrEmpty
    }
}