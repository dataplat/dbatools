#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaConnection",
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
                "SqlCredential",
                "SkipPSRemoting",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if command works" {
        It "returns the correct results" {
            $port = (Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle).Port
            $whoami = whoami

            $results = Test-DbaConnection -SqlInstance $TestConfig.InstanceSingle

            $results.TcpPort | Should -Be $port
            $results.AuthType | Should -Be 'Windows Authentication'
            $results.ConnectingAsUser | Should -Be $whoami
        }

        It "Returns output as a PSCustomObject" {
            $results | Should -Not -BeNullOrEmpty
            $results | Should -BeOfType PSCustomObject
        }

        It "Has the expected connection properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SqlVersion",
                "ConnectingAsUser",
                "ConnectSuccess",
                "AuthType",
                "AuthScheme",
                "TcpPort",
                "IPAddress",
                "NetBiosName",
                "IsPingable",
                "PSRemotingAccessible",
                "DomainName",
                "LocalWindows",
                "LocalPowerShell",
                "LocalCLR",
                "LocalSMOVersion",
                "LocalDomainUser",
                "LocalRunAsAdmin",
                "LocalEdition"
            )
            foreach ($prop in $expectedProps) {
                $results.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has valid connection status" {
            $results.ConnectSuccess | Should -BeTrue
        }
    }
}