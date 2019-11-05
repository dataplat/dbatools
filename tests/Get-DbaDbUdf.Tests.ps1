$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemUdf', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
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
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $CreateTestUDFunction -Database master
    }
    AfterAll {
        $DropTestUDFunction = "DROP FUNCTION dbo.dbatoolssci_ISOweek;"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $DropTestUDFunction -Database master
    }

    Context "Partition Functions are correctly located" {
        $results1 = Get-DbaDbUdf -SqlInstance $script:instance2 -Database master | Where-object {$_.name -eq 'dbatoolssci_ISOweek'} | Select-Object *
        $results2 = Get-DbaDbUdf -SqlInstance $script:instance2

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name dbo.dbatoolssci_ISOweek" {
            $results1.name | Should -Be 'dbatoolssci_ISOweek'
            $results1.schema | Should -Be 'dbo'
        }

        It "Should have a function type of Scalar " {
            $results1.FunctionType | Should -Be 'Scalar'
        }

        It "Should have Parameters of [@Date]" {
            $results1.Parameters | Should -Be "[@Date]"
        }

        It "Should not Throw an Error" {
            {Get-DbaDbUdf -SqlInstance $script:instance2 -ExcludeDatabase master -ExcludeSystemUdf } | Should -not -Throw
        }
    }
}