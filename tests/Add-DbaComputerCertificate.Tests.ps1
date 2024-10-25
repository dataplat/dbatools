#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaComputerCertificate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaComputerCertificate
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "SecurePassword",
                "Certificate",
                "Path",
                "Store",
                "Folder",
                "Flag",
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

Describe "Add-DbaComputerCertificate" -Tag "IntegrationTests" {
    Context "Certificate is added properly" {
        BeforeAll {
            $certPath = "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
            $results = Add-DbaComputerCertificate -Path $certPath -Confirm:$false
        }

        It "Should show the proper thumbprint has been added" {
            $results.Thumbprint | Should -Be "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "Should be in LocalMachine\My Cert Store" {
            $results.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
        }
    }
}
