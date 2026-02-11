#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegServerStore",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Components are properly retreived" {
        It "Should return the right values" {
            $results = Get-DbaRegServerStore -SqlInstance $TestConfig.InstanceSingle
            $results.InstanceName | Should -Not -Be $null
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaRegServerStore -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore"
        }

        It "Has the expected default display properties excluding internal properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("ServerConnection", "DomainInstanceName", "DomainName", "Urn", "Properties", "Metadata", "Parent", "ConnectionContext", "PropertyMetadataChanged", "PropertyChanged", "ParentServer")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }

        It "Has ComputerName, InstanceName, and SqlInstance in default display" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Contain "ComputerName" -Because "ComputerName should be in the default display set"
            $defaultProps | Should -Contain "InstanceName" -Because "InstanceName should be in the default display set"
            $defaultProps | Should -Contain "SqlInstance" -Because "SqlInstance should be in the default display set"
        }
    }
}