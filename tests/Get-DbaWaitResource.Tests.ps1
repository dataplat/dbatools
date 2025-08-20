#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWaitResource",
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
                "WaitResource",
                "Row",
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

        $random = Get-Random
        $WaitResourceDB = "WaitResource$random"
        Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -DatabaseName $WaitResourceDB -ReplaceDbNameInFile -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        $sql = "
                create table waittest (
                col1 int,
                col2 varchar(5)
                )
                go
                insert into waittest values (1,'hello')
                go
            "

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $WaitResourceDB -Query $sql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $WaitResourceDB | Remove-DbaDatabase -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Test getting a Page resource" {
        BeforeAll {
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
            $global:page = (Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $WaitResourceDB -Query $Pagesql).Column1
            $global:file = Get-DbaDbFile -SqlInstance $TestConfig.instance1 -Database $WaitResourceDB | Where-Object TypeDescription -eq "ROWS"
            $global:results = Get-DbaWaitResource -SqlInstance $TestConfig.instance1 -WaitResource $global:page
        }

        It "Should return databasename $WaitResourceDB" {
            $global:results.DatabaseName | Should -Be $WaitResourceDB
        }

        It "Should return physical filename" {
            $global:results.DataFilePath | Should -Be $global:file.PhysicalName
        }

        It "Should return the correct filename" {
            $global:results.DatafileName | Should -Be $global:file.LogicalName
        }

        It "Should return ObjectName waittest" {
            $global:results.ObjectName | Should -Be "waittest"
        }

        It "Should return the correct object type" {
            $global:results.ObjectType | Should -Be "USER_TABLE"
        }
    }

    Context "Deciphering a KEY WaitResource" {
        BeforeAll {
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
            $global:key = (Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $WaitResourceDB -Query $SqlKey).Column1
            $global:resultskey = Get-DbaWaitResource -SqlInstance $TestConfig.instance1 -WaitResource $global:key -row
        }

        It "Should Return DatabaseName $WaitResourceDB" {
            $global:results
        }

        It "Should return databasename $WaitResourceDB" {
            $global:resultskey.DatabaseName | Should -Be $WaitResourceDB
        }

        It "Should return SchemaName dbo" {
            $global:resultskey.SchemaName | Should -Be "dbo"
        }

        It "Should return indexname is idx_pester" {
            $global:resultskey.IndexName | Should -Be "idx_pester"
        }

        It "Should return ObjectName keytest" {
            $global:resultskey.ObjectName | Should -Be "Keytest"
        }

        It "SHould return col1 is 1" {
            $global:resultskey.ObjectData.col1 | Should -Be 1
        }

        It "Should return col1 is bilbo" {
            $global:resultskey.ObjectData.col2 | Should -Be "bilbo"
        }
    }
}