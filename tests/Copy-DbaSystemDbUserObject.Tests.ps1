param($ModuleName = 'dbatools')

Describe "Copy-DbaSystemDbUserObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

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
          SET @ISOweek=dbo.ISOweek(CAST(DATEPART(yy,@DATE)-1
               AS CHAR(4))+'12'+ CAST(24+DATEPART(DAY,@DATE) AS CHAR(2)))+1;
--Special case: Dec 29-31 may belong to the next year
     IF ((DATEPART(mm,@DATE)=12) AND
          ((DATEPART(dd,@DATE)-DATEPART(dw,@DATE))>= 28))
          SET @ISOweek=1;
     RETURN(@ISOweek);
END;
GO
SET DATEFIRST 1;
SELECT dbo.ISOweek(CONVERT(DATETIME,'12/26/2004',101)) AS 'ISO Week';
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
@range>= $1000 AND @range <$20000;
"@
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $Function
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $TableFunction
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $Rule
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "DROP FUNCTION dbo.dbatoolscs_ISOweek;"
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "DROP FUNCTION dbo.dbatoolsci_TableFunction;"
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "DROP RULE dbo.dbatoolsci_range_rule;"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaSystemDbUserObject
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have Classic as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Classic
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Should Copy Objects to the same instance" {
        It "Should execute with default parameters" {
            $results = Copy-DbaSystemDbUserObject -Source $global:instance2 -Destination $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with -Classic parameter" {
            $results = Copy-DbaSystemDbUserObject -Source $global:instance2 -Destination $global:instance2 -Classic
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with -Force parameter" {
            $results = Copy-DbaSystemDbUserObject -Source $global:instance2 -Destination $global:instance2 -Force
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
