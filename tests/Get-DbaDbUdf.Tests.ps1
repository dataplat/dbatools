#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbUdf",
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
                "ExcludeDatabase",
                "ExcludeSystemUdf",
                "Schema",
                "ExcludeSchema",
                "Name",
                "ExcludeName",
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

        #Test Function adapted from examples at:
        #https://docs.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql?view=sql-server-2017#examples
        $CreateTestUDFunction = @"
CREATE FUNCTION dbo.dbatoolssci_ISOweek (@DATE datetime)
RETURNS int
WITH EXECUTE AS CALLER
AS
BEGIN
     DECLARE @ISOweek int;
     SET @ISOweek= DATEPART(wk,@DATE)+1
          -DATEPART(wk,CAST(DATEPART(yy,@DATE) as CHAR(4))+'0104');
--Special cases: Jan 1-3 may belong to the previous year
     IF (@ISOweek=0)
          SET @ISOweek=dbo.ISOweek(CAST(DATEPART(yy,@DATE)-1
               AS CHAR(4))+'12'+ CAST(24+DATEPART(DAY,@DATE) AS CHAR(2)))+1;
--Special case: Dec 29-31 may belong to the next year
     IF ((DATEPART(mm,@DATE)=12) AND
          ((DATEPART(dd,@DATE)-DATEPART(dw,@DATE))>= 28))
          SET @ISOweek=1;
     RETURN(@ISOweek);
END;
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $CreateTestUDFunction -Database master

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DropTestUDFunction = "DROP FUNCTION dbo.dbatoolssci_ISOweek;"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $DropTestUDFunction -Database master -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "User Functions are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbUdf -SqlInstance $TestConfig.InstanceSingle -Database master -Name dbatoolssci_ISOweek | Select-Object *
            $results2 = Get-DbaDbUdf -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name dbo.dbatoolssci_ISOweek" {
            $results1.Name | Should -Be "dbatoolssci_ISOweek"
            $results1.Schema | Should -Be "dbo"
        }

        It "Should have a function type of Scalar" {
            $results1.FunctionType | Should -Be "Scalar"
        }

        It "Should have Parameters of [@Date]" {
            $results1.Parameters | Should -Be "[@Date]"
        }

        It "Should not Throw an Error" {
            { Get-DbaDbUdf -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase master -ExcludeSystemUdf } | Should -Not -Throw
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbUdf -SqlInstance $TestConfig.InstanceSingle -Database master -Name dbatoolssci_ISOweek
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.UserDefinedFunction"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
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
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}