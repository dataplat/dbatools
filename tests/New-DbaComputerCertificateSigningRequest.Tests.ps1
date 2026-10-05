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
                "Provider",
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
        $kspRequestFriendlyName = "dbatoolsci_csr_ksp_$(Get-Random)"
        $progressRequestFriendlyName = "dbatoolsci_csr_progress_$(Get-Random)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # certreq -new leaves the pending request with its private key in the REQUEST store of the local machine.
        $requestStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("REQUEST", "LocalMachine")
        $requestStore.Open("ReadWrite")
        foreach ($pendingRequest in ($requestStore.Certificates | Where-Object FriendlyName -in $requestFriendlyName, $kspRequestFriendlyName, $progressRequestFriendlyName)) {
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

    It "Generates the key in the Key Storage Provider when Provider asks for it" {
        # certreq keeps the key of a pending request with the request in LocalMachine\REQUEST, which is where the provider shows.
        $splatKspRequest = @{
            Path         = $requestPath
            FriendlyName = $kspRequestFriendlyName
            Provider     = "Microsoft Software Key Storage Provider"
        }
        $files = New-DbaComputerCertificateSigningRequest @splatKspRequest
        $files.Count | Should -Be 2
        $pendingRequest = Get-ChildItem -Path Cert:\LocalMachine\REQUEST | Where-Object FriendlyName -eq $kspRequestFriendlyName
        $pendingRequest | Should -Not -BeNullOrEmpty
        $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($pendingRequest)
        $privateKey.Key.Provider.Provider | Should -Be "Microsoft Software Key Storage Provider"
        $WarnVar | Should -BeNullOrEmpty
    }

    Context "When the pipeline ends at the first file" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. Select-Object -First 1 stops the command at
            # the first of the two files it returns. The request goes to a folder of its own, and the AfterAll
            # above removes it from the REQUEST store by its friendly name.
            $splatFirstFile = @{
                Path         = "$requestPath\progress"
                FriendlyName = $progressRequestFriendlyName
            }
            $requestRunspace = [runspacefactory]::CreateRunspace()
            $requestRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $requestRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $requestShell = [powershell]::Create()
            $requestShell.Runspace = $requestRunspace
            $firstFile = $requestShell.AddCommand("New-DbaComputerCertificateSigningRequest").AddParameters($splatFirstFile).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $requestRecords = @($requestShell.Streams.Progress)
            $requestShell.Dispose()
            $requestRunspace.Dispose()
        }

        It "Returns the first file" {
            @($firstFile).Count | Should -Be 1
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $requestRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $requestRecords | Where-Object Activity -eq "Executing New-DbaComputerCertificateSigningRequest" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}