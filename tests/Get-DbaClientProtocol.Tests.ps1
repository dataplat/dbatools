#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaClientProtocol",
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

Describe $CommandName -Tag IntegrationTests -Skip:(-not $env:appveyor) {
    # Skip on local tests as we don't get any results on SQL Server 2022

    Context "Get some client protocols" {
        It "Should return some protocols" {
            $results = @(Get-DbaClientProtocol)
            $results.Status.Count | Should -BeGreaterThan 1
            $results | Where-Object ProtocolDisplayName -eq "TCP/IP" | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaClientProtocol)
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.Management.Infrastructure.CimInstance"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "DisplayName", "DLL", "Order", "IsEnabled")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["ComputerName"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["ComputerName"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["DisplayName"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["DisplayName"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["DLL"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["DLL"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["Order"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Order"].MemberType | Should -Be "AliasProperty"
        }
    }
}