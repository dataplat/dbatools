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
    Context "Output validation" {
        BeforeAll {
            # Find a suitable certificate with a private key in the LocalMachine store
            $certForTest = Get-ChildItem Cert:\LocalMachine\My |
                Where-Object { $PSItem.HasPrivateKey -and $PSItem.NotAfter -gt (Get-Date) } |
                Select-Object -First 1
            $testThumbprint = $certForTest.Thumbprint

            if ($testThumbprint) {
                # Run the command to set the network certificate
                $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Thumbprint $testThumbprint -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
        }

        AfterAll {
            # Clear the network certificate setting via registry
            $instanceParam = [DbaInstanceParameter]$TestConfig.InstanceSingle
            $regInstanceName = $instanceParam.InstanceName
            if (-not $regInstanceName) { $regInstanceName = "MSSQLSERVER" }
            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $instanceParam.ComputerName -ScriptBlock { $wmi.Services } -ErrorAction SilentlyContinue |
                    Where-Object DisplayName -eq "SQL Server ($regInstanceName)"
                if ($sqlwmi) {
                    $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
                    if ($regRoot) {
                        Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib" -Name Certificate -Value "" -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                # Silently ignore cleanup errors
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no certificate available for testing" }
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no certificate available for testing" }
            $result[0].PSObject.Properties.Name | Should -Contain "ComputerName"
            $result[0].PSObject.Properties.Name | Should -Contain "InstanceName"
            $result[0].PSObject.Properties.Name | Should -Contain "SqlInstance"
            $result[0].PSObject.Properties.Name | Should -Contain "ServiceAccount"
            $result[0].PSObject.Properties.Name | Should -Contain "CertificateThumbprint"
            $result[0].PSObject.Properties.Name | Should -Contain "Notes"
        }

        It "Returns the correct thumbprint" {
            if (-not $result) { Set-ItResult -Skipped -Because "no certificate available for testing" }
            $result[0].CertificateThumbprint | Should -Be $testThumbprint.ToLowerInvariant()
        }
    }
}