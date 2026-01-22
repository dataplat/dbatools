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
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaConnection -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties for connection diagnostics" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SqlVersion',
                'ConnectingAsUser',
                'ConnectSuccess',
                'AuthType',
                'AuthScheme',
                'TcpPort',
                'IPAddress',
                'NetBiosName',
                'IsPingable',
                'PSRemotingAccessible',
                'DomainName',
                'LocalWindows',
                'LocalPowerShell',
                'LocalCLR',
                'LocalSMOVersion',
                'LocalDomainUser',
                'LocalRunAsAdmin',
                'LocalEdition'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns connection success status as boolean" {
            $result.ConnectSuccess | Should -BeOfType [bool]
        }

        It "Returns ping status as boolean" {
            $result.IsPingable | Should -BeOfType [bool]
        }

        It "Returns local domain user status as boolean" {
            $result.LocalDomainUser | Should -BeOfType [bool]
        }

        It "Returns local admin status as boolean" {
            $result.LocalRunAsAdmin | Should -BeOfType [bool]
        }
    }
}