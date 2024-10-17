param($ModuleName = 'dbatools')

Describe "Get-DbaPbmPolicy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmPolicy
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Policy as a parameter" {
            $CommandUnderTest | Should -HaveParameter Policy -Type String[]
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject[]
        }
        It "Should have IncludeSystemObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObject -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"

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

            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $conditionid = $server.ConnectionContext.ExecuteScalar($sqlconditionid)
            $objectsetid = $server.ConnectionContext.ExecuteScalar($sqlobjectsetid)
            $policyid = $server.ConnectionContext.ExecuteScalar($sqlpolicyid)
        }

        AfterAll {
            $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_policy @policy_id=$policyid")
            $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_id=$objectsetid")
            $server.Query("EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$conditionid")
        }

        It "returns the test policy" {
            $results = Get-DbaPbmPolicy -SqlInstance $script:instance2
            $results.Name | Should -Contain 'dbatoolsci_TestPolicy'
        }

        It "returns only the test policy named dbatoolsci_TestPolicy" {
            $results = Get-DbaPbmPolicy -SqlInstance $script:instance2 -Policy dbatoolsci_TestPolicy
            $results.Name | Should -Be 'dbatoolsci_TestPolicy'
        }

        It "returns a policy with a condition named dbatoolsci_Condition" {
            $results = Get-DbaPbmPolicy -SqlInstance $script:instance2 -Policy dbatoolsci_TestPolicy
            $results.Condition | Should -Be 'dbatoolsci_Condition'
        }
    }
}
