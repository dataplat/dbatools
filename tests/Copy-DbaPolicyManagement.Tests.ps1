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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $conditionName = "dbatoolsci_condition_$(Get-Random)"

        # Create a PBM condition on the source instance using proper expression XML format
        $expression = '<Operator>
  <TypeClass>Bool</TypeClass>
  <OpType>EQ</OpType>
  <Count>2</Count>
  <Attribute>
    <TypeClass>Bool</TypeClass>
    <Name>IsCaseSensitive</Name>
  </Attribute>
  <Function>
    <TypeClass>Bool</TypeClass>
    <FunctionType>True</FunctionType>
    <ReturnType>Bool</ReturnType>
    <Count>0</Count>
  </Function>
</Operator>'

        $createConditionSql = @"
DECLARE @condition_id int;
EXEC msdb.dbo.sp_syspolicy_add_condition
    @name = N'$conditionName',
    @description = N'dbatools CI test condition',
    @facet = N'Server',
    @expression = N'$expression',
    @is_name_condition = 0,
    @obj_name = N'',
    @condition_id = @condition_id OUTPUT;
"@

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createConditionSql

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup the condition on both instances
        $dropConditionSql = @"
IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = N'$conditionName')
    EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$conditionName';
"@

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dropConditionSql -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropConditionSql -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying policy management conditions" {
        It "Should copy the condition successfully" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                Condition   = $conditionName
            }
            $results = Copy-DbaPolicyManagement @splatCopy -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -BeNullOrEmpty
            $result = $results | Where-Object Name -eq $conditionName
            $result.Status | Should -Be "Successful"
            $result.Type | Should -Be "Policy Condition"
        }

        It "Should have the correct source and destination" {
            $result = $global:dbatoolsciOutput | Where-Object Name -eq $conditionName
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy2
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy1
        }

        It "Should have created the condition on the destination" {
            $checkSql = "SELECT name FROM msdb.dbo.syspolicy_conditions WHERE name = N'$conditionName'"
            $destCondition = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $checkSql
            $destCondition | Should -Not -BeNullOrEmpty
            $destCondition.name | Should -Be $conditionName
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputItem = ($global:dbatoolsciOutput | Where-Object { $null -ne $PSItem })[0]
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $outputItem | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $outputItem.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $outputItem.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
