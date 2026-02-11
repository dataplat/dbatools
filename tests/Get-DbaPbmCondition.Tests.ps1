#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCondition",
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
                "Condition",
                "InputObject",
                "IncludeSystemObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because working with policies is not supported.

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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $conditionId = $server.Query($conditionQuery) | Select-Object -ExpandProperty conditionId

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dropQuery = "EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$conditionId"
        $null = $server.Query($dropQuery)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command returns results" {
        BeforeAll {
            $results = Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle
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
            $results = Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition $conditionName
        }

        It "Should get results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have name property '$conditionName'" {
            $results.Name | Should -Be $conditionName
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition $conditionName
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Dmf.Condition"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "CreateDate",
                "CreatedBy",
                "DateModified",
                "Description",
                "ExpressionNode",
                "Facet",
                "HasScript",
                "IsSystemObject",
                "ModifiedBy"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}