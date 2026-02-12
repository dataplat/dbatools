#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaPolicyManagement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Policy",
                "ExcludePolicy",
                "Condition",
                "ExcludeCondition",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create a policy condition and policy on the source instance for testing.
        $conditionName = "dbatoolsci_outputcondition"
        $policyName = "dbatoolsci_outputpolicy"

        $splatQuerySource = @{
            SqlInstance = $TestConfig.InstanceCopy1
        }

        # Clean up any previous test artifacts
        try {
            Invoke-DbaQuery @splatQuerySource -Database msdb -Query "
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = '$policyName')
                    EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$policyName';
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = '$conditionName')
                    EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$conditionName';
            " -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }

        # Clean up destination too
        $splatQueryDest = @{
            SqlInstance = $TestConfig.InstanceCopy2
        }

        try {
            Invoke-DbaQuery @splatQueryDest -Database msdb -Query "
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = '$policyName')
                    EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$policyName';
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = '$conditionName')
                    EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$conditionName';
            " -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }

        # Create a condition and policy on the source using T-SQL stored procedures
        $createConditionSql = @"
EXEC msdb.dbo.sp_syspolicy_add_condition
    @name = N'$conditionName',
    @description = N'',
    @facet = N'Database',
    @expression = N'<Operator>
  <TypeClass>Bool</TypeClass>
  <OpType>EQ</OpType>
  <Count>2</Count>
  <Attribute>
    <TypeClass>Bool</TypeClass>
    <Name>AutoShrink</Name>
  </Attribute>
  <Function>
    <TypeClass>Bool</TypeClass>
    <FunctionType>False</FunctionType>
    <ReturnType>Bool</ReturnType>
    <Count>0</Count>
  </Function>
</Operator>',
    @is_name_condition = 0,
    @obj_name = N''
"@
        Invoke-DbaQuery @splatQuerySource -Database msdb -Query $createConditionSql

        $createPolicySql = @"
EXEC msdb.dbo.sp_syspolicy_add_policy
    @name = N'$policyName',
    @condition_name = N'$conditionName',
    @execution_mode = 0
"@
        Invoke-DbaQuery @splatQuerySource -Database msdb -Query $createPolicySql

        # Copy the policy to the destination
        $splatCopyPolicy = @{
            Source      = $TestConfig.InstanceCopy1
            Destination = $TestConfig.InstanceCopy2
            Policy      = $policyName
        }
        $result = @(Copy-DbaPolicyManagement @splatCopyPolicy)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up source
        try {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database msdb -Query "
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = '$policyName')
                    EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$policyName';
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = '$conditionName')
                    EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$conditionName';
            " -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }

        # Clean up destination
        try {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database msdb -Query "
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = '$policyName')
                    EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$policyName';
                IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = '$conditionName')
                    EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$conditionName';
            " -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the correct values for migration properties" {
            $result[0].SourceServer | Should -Not -BeNullOrEmpty
            $result[0].DestinationServer | Should -Not -BeNullOrEmpty
            $result[0].Status | Should -BeIn @("Successful", "Skipped", "Failed")
        }
    }
}