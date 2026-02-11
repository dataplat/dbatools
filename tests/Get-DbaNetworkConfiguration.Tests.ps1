#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkConfiguration",
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
                "OutputType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType TcpIpProperties
        }

        It "Should Return a Result" {
            $resultsFull | Should -Not -Be $null
            $resultsTcpIpProperties | Should -Not -Be $null
        }

        It "has the correct properties" {
            $expectedPropsFull = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SharedMemoryEnabled",
                "NamedPipesEnabled",
                "TcpIpEnabled",
                "TcpIpProperties",
                "TcpIpAddresses",
                "Certificate",
                "Advanced"
            )
            ($resultsFull.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsFull | Sort-Object)

            $expectedPropsTcpIpProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Enabled",
                "KeepAlive",
                "ListenAll"
            )
            ($resultsTcpIpProperties.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedPropsTcpIpProperties | Sort-Object)
        }
    }

    Context "Output validation" {
        BeforeAll {
            $resultFull = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle
            $resultCert = Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType Certificate
        }

        It "Returns output of type PSCustomObject for Full output" {
            if (-not $resultFull) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultFull | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties for Full output" {
            if (-not $resultFull) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SharedMemoryEnabled",
                "NamedPipesEnabled",
                "TcpIpEnabled",
                "TcpIpProperties",
                "TcpIpAddresses",
                "Certificate",
                "Advanced"
            )
            foreach ($prop in $expectedProps) {
                $resultFull.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has the expected default display properties for Certificate output" {
            if (-not $resultCert) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $resultCert[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ServiceAccount",
                "ForceEncryption",
                "FriendlyName",
                "DnsNameList",
                "Thumbprint",
                "Generated",
                "Expires",
                "IssuedTo",
                "IssuedBy"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}