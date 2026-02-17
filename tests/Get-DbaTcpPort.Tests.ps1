#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTcpPort",
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
                "All",
                "ExcludeIpv6",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command functionality" {
        BeforeAll {
            $results = Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $resultsIpv6 = Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle -All -ExcludeIpv6
            $resultsAll = Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle -All
        }

        It "Should return a result" {
            $results | Should -Not -Be $null
        }

        It "Has the correct properties" {
            $result = $results[0]
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IPAddress",
                "Port",
                "Static",
                "Type"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return multiple results when using All parameter" {
            $resultsAll.Count | Should -BeGreaterThan 1
        }

        It "Should exclude IPv6 results when using ExcludeIpv6 parameter" {
            $resultsAll.Count - $resultsIpv6.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IPAddress",
                "Port",
                "Static",
                "Type"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IPAddress",
                "Port"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}