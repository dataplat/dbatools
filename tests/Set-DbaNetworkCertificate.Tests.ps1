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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create a certificate for testing
        $testCert = New-DbaComputerCertificate -ComputerName $TestConfig.instance1 -WarningAction SilentlyContinue
        $testThumbprint = $testCert.Thumbprint

        # Set the network certificate and capture output
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.instance1 -Thumbprint $testThumbprint -Confirm:$false -OutVariable "global:dbatoolsciOutput" -WarningAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the network certificate we set
        $null = Remove-DbaNetworkCertificate -SqlInstance $TestConfig.instance1 -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setting a network certificate" {
        It "Should return results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should have the correct thumbprint" {
            $result.CertificateThumbprint | Should -Be $testThumbprint.ToLowerInvariant()
        }

        It "Should have a service account" {
            $result.ServiceAccount | Should -Not -BeNullOrEmpty
        }

        It "Should include notes about granting permissions" {
            $result.Notes | Should -Match "Granted .+ read access to certificate private key"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $skipOutput = $null -eq $global:dbatoolsciOutput -or $global:dbatoolsciOutput.Count -eq 0
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" -Skip:$skipOutput {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" -Skip:$skipOutput {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ServiceAccount",
                "CertificateThumbprint",
                "Notes"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            foreach ($prop in $expectedProperties) {
                $prop | Should -BeIn $actualProperties
            }
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}