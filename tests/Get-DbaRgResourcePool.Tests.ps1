#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgResourcePool",
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
                "Type",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting resource pools" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $allResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "When getting resource pools using -Type parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $typeResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type Internal
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results with Type filter" {
            $typeResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ResourcePool]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "CapCpuPercentage",
                "IsSystemObject",
                "MaximumCpuPercentage",
                "MaximumIopsPerVolume",
                "MaximumMemoryPercentage",
                "MinimumCpuPercentage",
                "MinimumIopsPerVolume",
                "MinimumMemoryPercentage",
                "WorkloadGroups"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ResourcePool"
        }
    }
}