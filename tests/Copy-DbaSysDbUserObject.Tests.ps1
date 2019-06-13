$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Force', 'Classic', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
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
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $Function
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $TableFunction
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $Rule
    }
    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "DROP FUNCTION dbo.dbatoolscs_ISOweek;"
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "DROP FUNCTION dbo.dbatoolsci_TableFunction;"
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "DROP RULE dbo.dbatoolsci_range_rule;"
    }

    Context "Should Copy Objects to the same instance" {
        $results = Copy-DbaSysDbUserObject -Source $script:instance2 -Destination $script:instance2
        It "Should execute with default parameters" {
            $results | Should Not Be Null
        }

        $results = Copy-DbaSysDbUserObject -Source $script:instance2 -Destination $script:instance2 -Classic
        It "Should execute with -Classic parameter" {
            $results | Should Not Be Null
        }

        $results = Copy-DbaSysDbUserObject -Source $script:instance2 -Destination $script:instance2 -Force
        It "Should execute with -Classic parameter" {
            $results | Should Not Be Null
        }
    }
}