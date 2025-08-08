#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaComputerCertificate",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $CommandName
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

        foreach ($param in $expected) {
            It "Has parameter: $param" {
                $command | Should -HaveParameter $param
            }
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $certThumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        $certPath = "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt"
        $backupPath = $TestConfig.Temp

        $null = Add-DbaComputerCertificate -Path $certPath

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaComputerCertificate -Thumbprint $certThumbprint -ErrorAction SilentlyContinue
    }

    Context "Certificate is backed up properly" {
        BeforeAll {
            $result = Get-DbaComputerCertificate -Thumbprint $certThumbprint | Backup-DbaComputerCertificate -Path $backupPath
        }

        AfterAll {
            Get-ChildItem -Path $result.FullName -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
        }

        It "Returns the proper results" {
            $result.Name | Should -Match "$certThumbprint.cer"
        }
    }
}
