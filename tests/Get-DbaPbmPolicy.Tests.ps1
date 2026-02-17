#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmPolicy",
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
                "Policy",
                "Category",
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

        $sqlconditionid = "DECLARE @condition_id INT
                EXEC msdb.dbo.sp_syspolicy_add_condition @name=N'dbatoolsci_Condition', @description=N'', @facet=N'ApplicationRole', @expression=N'<Operator>
                  <TypeClass>Bool</TypeClass>
                  <OpType>EQ</OpType>
                  <Count>2</Count>
                  <Attribute>
                    <TypeClass>DateTime</TypeClass>
                    <Name>DateLastModified</Name>
                  </Attribute>
                  <Function>
                    <TypeClass>DateTime</TypeClass>
                    <FunctionType>DateTime</FunctionType>
                    <ReturnType>DateTime</ReturnType>
                    <Count>1</Count>
                    <Constant>
                      <TypeClass>String</TypeClass>
                      <ObjType>System.String</ObjType>
                      <Value>2016-05-03T00:00:00.0000000</Value>
                    </Constant>
                  </Function>
                </Operator>', @is_name_condition=0, @obj_name=N'', @condition_id=@condition_id OUTPUT
                SELECT @condition_id"

        $sqlobjectsetid = "DECLARE @object_set_id INT
        EXEC msdb.dbo.sp_syspolicy_add_object_set @object_set_name=N'dbatoolsci_TestPolicy_ObjectSet', @facet=N'ApplicationRole', @object_set_id=@object_set_id OUTPUT
        SELECT @object_set_id"

        $sqlpolicyid = "DECLARE @policy_id INT
        EXEC msdb.dbo.sp_syspolicy_add_policy @name=N'dbatoolsci_TestPolicy', @condition_name=N'dbatoolsci_Condition', @policy_category=N'', @description=N'', @help_text=N'', @help_link=N'', @schedule_uid=N'00000000-0000-0000-0000-000000000000', @execution_mode=2, @is_enabled=True, @policy_id=@policy_id OUTPUT, @root_condition_name=N'', @object_set=N'dbatoolsci_TestPolicy_ObjectSet'
        SELECT @policy_id"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $conditionid = $server.ConnectionContext.ExecuteScalar($sqlconditionid)
        $objectsetid = $server.ConnectionContext.ExecuteScalar($sqlobjectsetid)
        $policyid = $server.ConnectionContext.ExecuteScalar($sqlpolicyid)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_policy @policy_id=$policyid")
        $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_id=$objectsetid")
        $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$conditionid")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When retrieving PBM policies" {
        It "returns the test policy" {
            $results = Get-DbaPbmPolicy -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results.Name -contains "dbatoolsci_TestPolicy" | Should -Be $true
        }

        It "returns only the test policy named dbatoolsci_TestPolicy" {
            $results = Get-DbaPbmPolicy -SqlInstance $TestConfig.InstanceSingle -Policy dbatoolsci_TestPolicy
            $results.Name -eq "dbatoolsci_TestPolicy" | Should -Be $true
        }

        It "returns a policy with a condition named dbatoolsci_Condition" {
            $results = Get-DbaPbmPolicy -SqlInstance $TestConfig.InstanceSingle -Policy dbatoolsci_TestPolicy
            $results.Condition -eq "dbatoolsci_Condition" | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.Policy]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ID",
                "Name",
                "Enabled",
                "Description",
                "PolicyCategory",
                "AutomatedPolicyEvaluationMode",
                "Condition",
                "CreateDate",
                "CreatedBy",
                "DateModified",
                "ModifiedBy",
                "IsSystemObject",
                "ObjectSet",
                "RootCondition",
                "ScheduleUid"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Dmf\.Policy"
        }
    }
}