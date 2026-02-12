#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceProtocol",
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
    Context "Command actually works" {
        BeforeAll {
            $allResults = Get-DbaInstanceProtocol -ComputerName $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $tcpResults = $allResults | Where-Object Name -eq "Tcp"
        }

        It "shows some services" {
            $allResults.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "can get TCPIP" {
            foreach ($result in $tcpResults) {
                $result.Name -eq "Tcp" | Should -Be $true
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaInstanceProtocol -ComputerName $TestConfig.InstanceSingle
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "DisplayName", "Name", "MultiIP", "IsEnabled")
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
            $result[0].psobject.Properties["Name"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Name"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["MultiIP"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["MultiIP"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["IsEnabled"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["IsEnabled"].MemberType | Should -Be "AliasProperty"
        }
    }
}