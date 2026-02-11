#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAgSpn",
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
                "Credential",
                "AvailabilityGroup",
                "Listener",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $result = Test-DbaAgSpn -SqlInstance $TestConfig.InstanceHadr
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "ComputerName",
                "SqlInstance",
                "InstanceName",
                "SqlProduct",
                "InstanceServiceAccount",
                "RequiredSPN",
                "IsSet",
                "Cluster",
                "TcpEnabled",
                "Port",
                "DynamicPort",
                "Warning",
                "Error"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the expected default display properties excluding Credential and DomainName" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Credential" -Because "Credential should be excluded from default display"
            $defaultProps | Should -Not -Contain "DomainName" -Because "DomainName should be excluded from default display"
        }
    }
}
