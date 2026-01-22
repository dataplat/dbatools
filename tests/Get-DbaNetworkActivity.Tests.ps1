#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkActivity",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets Network Activity" {
        It "Gets results" {
            $results = Get-DbaNetworkActivity -ComputerName $env:ComputerName
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaNetworkActivity -ComputerName $env:ComputerName -EnableException
        }

        It "Returns the documented output type" {
            $result[0].PSObject.TypeNames | Should -Contain 'Win32_PerfFormattedData_Tcpip_NetworkInterface'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'NIC',
                'BytesReceivedPersec',
                'BytesSentPersec',
                'BytesTotalPersec',
                'Bandwidth'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}