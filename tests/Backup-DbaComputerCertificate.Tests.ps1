#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Backup-DbaComputerCertificate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Backup-DbaComputerCertificate
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "SecurePassword",
                "InputObject",
                "Path",
                "FilePath",
                "Type",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $command.Parameters.Keys | Should -BeNullOrEmpty
        }
    }
}

Describe "Backup-DbaComputerCertificate" -Tag "IntegrationTests" {
    Context "Certificate is added and backed up properly" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt" -Confirm:$false
            $certThumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $backupPath = "C:\temp"
        }

        It "Returns the proper results" {
            $result = Get-DbaComputerCertificate -Thumbprint $certThumbprint | Backup-DbaComputerCertificate -Path $backupPath
            $result.Name | Should -Match "$certThumbprint.cer"
        }

        AfterAll {
            $null = Remove-DbaComputerCertificate -Thumbprint $certThumbprint -Confirm:$false
        }
    }
}
