#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMsdtc",
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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "returns results" {
            $results = Get-DbaMsdtc -ComputerName $env:COMPUTERNAME
            $results.DTCServiceName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaMsdtc -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "DTCServiceName",
                "DTCServiceState",
                "DTCServiceStatus",
                "DTCServiceStartMode",
                "DTCServiceAccount",
                "DTCCID_MSDTC",
                "DTCCID_MSDTCUIS",
                "DTCCID_MSDTCTIPGW",
                "DTCCID_MSDTCXATM",
                "networkDTCAccess",
                "networkDTCAccessAdmin",
                "networkDTCAccessClients",
                "networkDTCAccessInbound",
                "networkDTCAccessOutBound",
                "networkDTCAccessTip",
                "networkDTCAccessTransactions",
                "XATransactions"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }
    }
}