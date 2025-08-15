#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmCondition",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Condition",
                "InputObject",
                "IncludeSystemObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $conditionName = "dbatoolsCondition_$(Get-Random)"
        $conditionQuery = @"
            Declare @condition_id int
            EXEC msdb.dbo.sp_syspolicy_add_condition @name=N'$conditionName', @description=N'', @facet=N'Database', @expression=N'<Operator>
            <TypeClass>Bool</TypeClass>
            <OpType>EQ</OpType>
            <Count>2</Count>
            <Attribute>
                <TypeClass>String</TypeClass>
                <Name>Name</Name>
            </Attribute>
            <Constant>
                <TypeClass>String</TypeClass>
                <ObjType>System.String</ObjType>
                <Value>test</Value>
            </Constant>
            </Operator>', @is_name_condition=1, @obj_name=N'test', @condition_id=@condition_id OUTPUT
            Select @condition_id as conditionId
"@

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $conditionId = $server.Query($conditionQuery) | Select-Object -ExpandProperty conditionId

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dropQuery = "EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$conditionId"
        $null = $server.Query($dropQuery)

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command returns results" {
        BeforeAll {
            $results = Get-DbaPbmCondition -SqlInstance $TestConfig.instance2
        }

        It "Should get results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have name property '$conditionName'" {
            $results.Name | Should -Contain $conditionName
        }
    }

    Context "Command actually works by condition name" {
        BeforeAll {
            $results = Get-DbaPbmCondition -SqlInstance $TestConfig.instance2 -Condition $conditionName
        }

        It "Should get results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have name property '$conditionName'" {
            $results.Name | Should -Be $conditionName
        }
    }
}