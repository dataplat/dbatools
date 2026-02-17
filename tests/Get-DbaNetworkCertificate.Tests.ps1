#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkCertificate",
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
        BeforeAll {
            $result = Get-DbaNetworkCertificate -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput" -WarningAction SilentlyContinue
        }

        It "Should execute without errors" {
            { Get-DbaNetworkCertificate -SqlInstance $TestConfig.instance1 -WarningAction SilentlyContinue } | Should -Not -Throw
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
                "VSName",
                "ServiceAccount",
                "ForceEncryption",
                "FriendlyName",
                "DnsNameList",
                "Thumbprint",
                "Generated",
                "Expires",
                "IssuedTo",
                "IssuedBy",
                "Certificate"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" -Skip:$skipOutput {
            $expectedColumns = @(
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
            if ($global:dbatoolsciOutput[0].VSName) {
                $expectedColumns = @("ComputerName", "InstanceName", "SqlInstance", "VSName", "ServiceAccount", "ForceEncryption", "FriendlyName", "DnsNameList", "Thumbprint", "Generated", "Expires", "IssuedTo", "IssuedBy")
            }
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}