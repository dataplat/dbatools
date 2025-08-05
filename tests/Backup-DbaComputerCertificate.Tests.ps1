#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Backup-DbaComputerCertificate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Backup-DbaComputerCertificate
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SecurePassword",
                "InputObject",
                "Path",
                "FilePath",
                "Type",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Backup-DbaComputerCertificate" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $certThumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        $certPath = "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
        $backupPath = $TestConfig.Temp

        $null = Add-DbaComputerCertificate -Path $certPath

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $null = Remove-DbaComputerCertificate -Thumbprint $certThumbprint
    }

    Context "Certificate is backed up properly" {
        BeforeAll {
            $result = Get-DbaComputerCertificate -Thumbprint $certThumbprint | Backup-DbaComputerCertificate -Path $backupPath
        }

        AfterAll {
            Get-ChildItem -Path $result.FullName | Remove-Item
        }

        It "Returns the proper results" {
            $result.Name | Should -Match "$certThumbprint.cer"
        }
    }
}
