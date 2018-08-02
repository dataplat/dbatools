<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {

        $random = Get-Random
        $WaitResourceDB = "WaitResource$random"
        Restore-DbaDatabase -SqlInstance $script:instance1 -DatabaseName $WaitResourceDB -ReplaceDbNameInFile -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak
        $sql = "
                create table waittest (
                col1 int,
                col2 varchar(5)
                )
                go
                insert into waittest values (1,'hello')
                go
            "
        
        Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database $WaitResourceDB -Query $sql
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $WaitResourceDB | Remove-DbaDatabase -Confirm:$false

    }

    Context "Test getting a Page resource"{
        $PageSql = "
            Create table #TmpIndex(
                PageFiD int,
                PagePid int,
                IAMFID int,
                IAMPid int,
                ObjectID int,
                IndexID int,
                PartitionNumber bigint,
                ParitionId bigint,
                iam_chain_type varchar(50),
                PageType int,
                IndexLevel int,
                NextPageFID int,
                NextPagePID int,
                prevPageFid int,
                PrevPagePID int
            );

            insert #TmpIndex exec ('dbcc ind($WaitResourceDb,waittest,-1)')

            declare @pageid int
            select @pageid=PagePid from #TmpIndex where PageType=10
            select 'PAGE: '+convert(varchar(3),DB_ID())+':1:'+convert(varchar(15),@pageid)
        "
       $page =  (Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database $WaitResourceDB -Query $Pagesql).Column1
       $file = Get-DbaDatabaseFile -SqlInstance $script:instance1 -Database $WaitResourceDB | Where-Object TypeDescription -eq 'ROWS'
       $results = Get-DbaWaitResource -SqlInstance $script:instance1 -WaitResource $page
       It "Should return databasename $WaitResourceDB" {
           $results.DatabaseName | Should Be $WaitResourceDB
       }
       
       It "Should return physical filename" {
           $results.DataFilePath | Should Be $file.PhysicalName
       }
       It "Should return the correct filename" {
           $results.DatafileName | Should Be $file.LogicalName
       }
       It "Should return ObjectName waittest" {
           $results.ObjectName | Should be 'waittest'
       }
       It "Should return the correct object type" {
           $Results.ObjectType | Should Be 'USER_TABLE'
       }
    }

    Context "Deciphering a KEY WaitResource" {
        $SqlKey = "
            create table keytest(
                col1 int,
                col2 varchar(5)
            )

            create clustered index idx_pester on keytest (col1)

            insert into keytest values (1,'bilbo')

            declare @hobt_id bigint
            select @hobt_id = hobt_id from sys.partitions where object_id=object_id('dbo.keytest')

            select 'KEY: '+convert(varchar(3),db_id())+':'+convert(varchar(30),@hobt_id)+' '+ %%lockres%% from keytest  where col1=1
        "
        $key = (Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database $WaitResourceDB -Query $SqlKey).Column1
        $resultskey = Get-DbaWaitResource -SqlInstance $script:instance1 -WaitResource $key -row
        It "Should Return DatabaseName $WaitResourceDB" {
            $results
        }
        It "Should return databasename $WaitResourceDB" {
            $resultskey.DatabaseName | Should Be $WaitResourceDB
        }
        It "Should return SchemaName dbo" {
            $resultskey.SchemaName | Should Be 'dbo'
        }
        It "Should return indexname is idx_pester" {
            $resultskey.IndexName | Should Be 'idx_pester'
        }
        It "Should return ObjectName keytest"{
            $resultskey.ObjectName | Should Be 'Keytest'
        }
        It "SHould return col1 is 1" {
            $resultskey.ObjectData.col1 | Should Be 1
        }
        It "Should return col1 is bilbo" {
            $resultskey.ObjectData.col2 | Should Be 'bilbo'
        }
    }
}