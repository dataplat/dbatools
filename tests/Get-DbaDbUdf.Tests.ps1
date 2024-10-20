param($ModuleName = 'dbatools')

Describe "Get-DbaDbUdf Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbUdf
        }
        It "has the required parameter: <_>" -ForEach @(
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
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbUdf Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
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
        Invoke-DbaQuery -SqlInstance $global:instance2 -Query $CreateTestUDFunction -Database master
    }

    AfterAll {
        $DropTestUDFunction = "DROP FUNCTION dbo.dbatoolssci_ISOweek;"
        Invoke-DbaQuery -SqlInstance $global:instance2 -Query $DropTestUDFunction -Database master
    }

    Context "User Functions are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbUdf -SqlInstance $global:instance2 -Database master -Name dbatoolssci_ISOweek | Select-Object *
            $results2 = Get-DbaDbUdf -SqlInstance $global:instance2
        }

        It "Should execute and return results" {
            $results2 | Should -Not -BeNullOrEmpty
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -BeNullOrEmpty
        }

        It "Should have matching name dbo.dbatoolssci_ISOweek" {
            $results1.name | Should -Be 'dbatoolssci_ISOweek'
            $results1.schema | Should -Be 'dbo'
        }

        It "Should have a function type of Scalar" {
            $results1.FunctionType | Should -Be 'Scalar'
        }

        It "Should have Parameters of [@Date]" {
            $results1.Parameters | Should -Be "[@Date]"
        }

        It "Should not Throw an Error" {
            { Get-DbaDbUdf -SqlInstance $global:instance2 -ExcludeDatabase master -ExcludeSystemUdf } | Should -Not -Throw
        }
    }
}
