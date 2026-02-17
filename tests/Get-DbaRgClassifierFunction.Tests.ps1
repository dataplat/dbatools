#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgClassifierFunction",
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
                "InputObject",
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

        $sql = @"
CREATE FUNCTION dbatoolsci_fnRG()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
     RETURN N'gOffHoursProcessing'
END
"@

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $sql
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG]"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "Returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be "dbatoolsci_fnRG"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.UserDefinedFunction]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "CreateDate",
                "DateLastModified",
                "Name",
                "DataType"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.UserDefinedFunction"
        }
    }
}