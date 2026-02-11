#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileGrowth",
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
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "returns information about msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle
            $result.Database -contains "msdb" | Should -Be $true
        }
    }

    Context "Should return file information for only msdb" {
        It "returns only msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1
            $result.Database | Should -Be "msdb"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "MaxSize",
                "GrowthType",
                "Growth",
                "File",
                "FileName",
                "State"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["File"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["File"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["FileName"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["FileName"].MemberType | Should -Be "AliasProperty"
        }
    }
}