#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaResourceGovernor",
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
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the correct ComputerName" {
            $results.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Should have the Enabled property" {
            $results.Enabled | Should -Not -BeNullOrEmpty
        }

        It "Should have ResourcePools" {
            $results.ResourcePools | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ResourceGovernor]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ClassifierFunction",
                "Enabled",
                "MaxOutstandingIOPerVolume",
                "ReconfigurePending",
                "ResourcePools",
                "ExternalResourcePools"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ResourceGovernor"
        }
    }
}