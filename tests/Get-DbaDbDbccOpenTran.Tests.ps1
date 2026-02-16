#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDbccOpenTran",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets results for Open Transactions" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Cmd",
                "Output",
                "Field",
                "Data"
            )
        }

        It "returns results for DBCC OPENTRAN" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
        }

        It "returns multiple results" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return all expected properties" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }

        It "returns results for a specific database" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.InstanceSingle -Database tempDB
            $tempDB = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempDB

            $result | Should -Not -BeNullOrEmpty
            $result.Database | Get-Unique | Should -Be "tempDB"
            $result.DatabaseId | Get-Unique | Should -Be $tempDB.Id
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
                "Database",
                "DatabaseId",
                "Cmd",
                "Output",
                "Field",
                "Data"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}