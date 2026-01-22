#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSystemDbUserObject",
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
                "Force",
                "Classic",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        #Function Scripts roughly From https://docs.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql
        #Rule Scripts roughly from https://docs.microsoft.com/en-us/sql/t-sql/statements/create-rule-transact-sql
        $Function = @"
CREATE FUNCTION dbo.dbatoolscs_ISOweek (@DATE datetime)
RETURNS int
WITH EXECUTE AS CALLER
AS
BEGIN
     DECLARE @ISOweek int;
     SET @ISOweek= DATEPART(wk,@DATE)+1
          -DATEPART(wk,CAST(DATEPART(yy,@DATE) as CHAR(4))+'0104');
--Special cases: Jan 1-3 may belong to the previous year
     IF (@ISOweek=0)
          SET @ISOweek=dbo.dbatoolscs_ISOweek(CAST(DATEPART(yy,@DATE)-1
               AS CHAR(4))+'12'+ CAST(24+DATEPART(DAY,@DATE) AS CHAR(2)))+1;
--Special case: Dec 29-31 may belong to the next year
     IF ((DATEPART(mm,@DATE)=12) AND
          ((DATEPART(dd,@DATE)-DATEPART(dw,@DATE))>= 28))
          SET @ISOweek=1;
     RETURN(@ISOweek);
END;
GO
SET DATEFIRST 1;
SELECT dbo.dbatoolscs_ISOweek(CONVERT(DATETIME,'12/26/2004',101)) AS 'ISO Week';
"@
        $TableFunction = @"
CREATE FUNCTION dbo.dbatoolsci_TableFunction (@pid int)
RETURNS TABLE
AS
RETURN
(
    select spid,kpid,blocked,waittype,waittime,lastwaittype,waitresource,dbid,uid,cpu,physical_io
    from sys.sysprocesses where spid = @pid
);
GO
"@
        $Rule = @"
CREATE RULE dbo.dbatoolsci_range_rule
AS
@range>= 1000 AND @range <20000;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $Function
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $TableFunction
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $Rule
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "DROP FUNCTION dbo.dbatoolscs_ISOweek;"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "DROP FUNCTION dbo.dbatoolsci_TableFunction;"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "DROP RULE dbo.dbatoolsci_range_rule;"
    }

    Context "When copying objects to the same instance" {
        It "Should execute successfully with default parameters" {
            $results = Copy-DbaSystemDbUserObject -Source $TestConfig.InstanceSingle -Destination $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute successfully with -Classic parameter" {
            $results = Copy-DbaSystemDbUserObject -Source $TestConfig.InstanceSingle -Destination $TestConfig.InstanceSingle -Classic
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute successfully with -Force parameter" {
            $results = Copy-DbaSystemDbUserObject -Source $TestConfig.InstanceSingle -Destination $TestConfig.InstanceSingle -Force
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Copy-DbaSystemDbUserObject -Source $TestConfig.InstanceSingle -Destination $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has DateTime property of type DbaDateTime" {
            $result[0].DateTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        }

        It "Has SourceServer property populated" {
            $result[0].SourceServer | Should -Not -BeNullOrEmpty
        }

        It "Has DestinationServer property populated" {
            $result[0].DestinationServer | Should -Not -BeNullOrEmpty
        }

        It "Has Status property with valid values" {
            $validStatuses = @("Successful", "Skipped", "Failed")
            $result[0].Status | Should -BeIn $validStatuses
        }
    }

    Context "Output with -Classic" {
        It "Returns no output when -Classic specified" {
            $result = Copy-DbaSystemDbUserObject -Source $TestConfig.InstanceSingle -Destination $TestConfig.InstanceSingle -Classic
            $result | Should -BeNullOrEmpty
        }
    }
}