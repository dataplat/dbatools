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
        Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -DatabaseName $WaitResourceDB -ReplaceDbNameInFile -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        $sql = "
                create table waittest (
                col1 int,
                col2 varchar(5)
                )
                go
                insert into waittest values (1,'hello')
                go
            "

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $WaitResourceDB -Query $sql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $WaitResourceDB | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            $page = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $WaitResourceDB -Query $Pagesql).Column1
            $file = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $WaitResourceDB | Where-Object TypeDescription -eq "ROWS"
            $results = Get-DbaWaitResource -SqlInstance $TestConfig.InstanceSingle -WaitResource $page
        }

        It "Should return databasename $WaitResourceDB" {
            $results.DatabaseName | Should -Be $WaitResourceDB
        }

        It "Should return physical filename" {
            $results.DataFilePath | Should -Be $file.PhysicalName
        }

        It "Should return the correct filename" {
            $results.DatafileName | Should -Be $file.LogicalName
        }

        It "Should return ObjectName waittest" {
            $results.ObjectName | Should -Be "waittest"
        }

        It "Should return the correct object type" {
            $results.ObjectType | Should -Be "USER_TABLE"
        }

        It "Returns output of type PSCustomObject" {
            $results | Should -Not -BeNullOrEmpty
            $results | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected PAGE properties" {
            $expectedProps = @("DatabaseID", "DatabaseName", "DataFileName", "DataFilePath", "ObjectID", "ObjectName", "ObjectSchema", "ObjectType")
            foreach ($prop in $expectedProps) {
                $results.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on PAGE wait resource output"
            }
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
            $key = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $WaitResourceDB -Query $SqlKey).Column1
            $resultskey = Get-DbaWaitResource -SqlInstance $TestConfig.InstanceSingle -WaitResource $key -row
        }

        It "Should Return DatabaseName $WaitResourceDB" {
            $results
        }

        It "Should return databasename $WaitResourceDB" {
            $resultskey.DatabaseName | Should -Be $WaitResourceDB
        }

        It "Should return SchemaName dbo" {
            $resultskey.SchemaName | Should -Be "dbo"
        }

        It "Should return indexname is idx_pester" {
            $resultskey.IndexName | Should -Be "idx_pester"
        }

        It "Should return ObjectName keytest" {
            $resultskey.ObjectName | Should -Be "Keytest"
        }

        It "SHould return col1 is 1" {
            $resultskey.ObjectData.col1 | Should -Be 1
        }

        It "Should return col1 is bilbo" {
            $resultskey.ObjectData.col2 | Should -Be "bilbo"
        }

        It "Returns output of type PSCustomObject for KEY" {
            $resultskey | Should -Not -BeNullOrEmpty
            $resultskey | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected KEY properties" {
            $expectedProps = @("DatabaseID", "DatabaseName", "SchemaName", "IndexName", "ObjectID", "ObjectName", "HobtID")
            foreach ($prop in $expectedProps) {
                $resultskey.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on KEY wait resource output"
            }
        }
    }

}
