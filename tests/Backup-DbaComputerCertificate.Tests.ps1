#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaComputerCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SecurePassword",
                "InputObject",
                "Path",
                "FilePath",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because we need code changes (X509Certificate is immutable on this platform. Use the equivalent constructor instead.)

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test certificate backup, we need a certificate installed on the computer.

        # Set variables. They are available in all the It blocks.
        $certThumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        $certPath = "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"

        # Create the objects.
        $null = Add-DbaComputerCertificate -Path $certPath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $null = Remove-DbaComputerCertificate -Thumbprint $certThumbprint -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Certificate is backed up properly" {
        It "Returns the proper results" {
            $backupResult = Get-DbaComputerCertificate -Thumbprint $certThumbprint | Backup-DbaComputerCertificate -Path $backupPath
            $backupResult.Name | Should -Match "$certThumbprint.cer"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaComputerCertificate -Thumbprint $certThumbprint | Backup-DbaComputerCertificate -Path $backupPath -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'Name',
                'FullName',
                'DirectoryName',
                'Directory',
                'Extension',
                'Length',
                'CreationTime',
                'LastWriteTime',
                'Attributes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in FileInfo output"
            }
        }
    }
}