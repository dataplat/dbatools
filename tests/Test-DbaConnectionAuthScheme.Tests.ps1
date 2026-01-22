#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaConnectionAuthScheme",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Kerberos",
                "Ntlm",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns the proper transport" {
        It "returns ntlm auth scheme" {
            $results = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.InstanceSingle
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                $results.AuthScheme | Should -Be 'ntlm'
            } else {
                $results.AuthScheme | Should -Be 'KERBEROS'
            }

        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Transport',
                'AuthScheme'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties from sys.dm_exec_connections" {
            $additionalProps = @(
                'SessionId',
                'ConnectTime',
                'ProtocolType',
                'PacketSize',
                'ClientNetworkAddress'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }

    Context "Output with -Kerberos switch" {
        BeforeAll {
            $result = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.instance1 -Kerberos -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties for Kerberos check" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Result'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present with -Kerberos"
            }
        }

        It "Result property is a boolean" {
            $result.Result | Should -BeOfType [bool]
        }
    }

    Context "Output with -Ntlm switch" {
        BeforeAll {
            $result = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.instance1 -Ntlm -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties for NTLM check" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Result'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present with -Ntlm"
            }
        }

        It "Result property is a boolean" {
            $result.Result | Should -BeOfType [bool]
        }
    }
}