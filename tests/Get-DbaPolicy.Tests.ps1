$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
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

        $results = Get-DbaPolicy -SqlInstance $script:instance2

        It "returns the test policy" {
            $results.Name -contains 'dbatoolsci_TestPolicy' | Should Be $true
        }

        $results = Get-DbaPolicy -SqlInstance $script:instance2 -Policy dbatoolsci_TestPolicy

        It "returns only the test policy named dbatoolsci_TestPolicy" {
            $results.Name -eq 'dbatoolsci_TestPolicy' | Should Be $true
        }

        It "returns a policy with a condition named dbatoolsci_Condition" {
            $results.Condition -eq 'dbatoolsci_Condition' | Should Be $true
        }
    }
}
