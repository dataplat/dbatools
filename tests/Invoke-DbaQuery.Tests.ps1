#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaQuery",
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
                "Query",
                "QueryTimeout",
                "File",
                "SqlObject",
                "As",
                "SqlParameter",
                "AppendServerInstance",
                "MessagesToOutput",
                "InputObject",
                "ReadOnly",
                "EnableException",
                "CommandType",
                "NoExec",
                "QuotedIdentifier",
                "AppendConnectionString"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
    Context "Validate alias" {
        It "Should contain the alias: ivq" {
            (Get-Alias ivq) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
        $null = $db.Query("CREATE PROCEDURE dbo.dbatoolsci_procedure_example @p1 [INT] = 0 AS BEGIN SET NOCOUNT OFF; SELECT TestColumn = @p1; END")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $null = $db.Query("DROP PROCEDURE dbo.dbatoolsci_procedure_example")
            $null = $db.Query("DROP PROCEDURE dbo.my_proc")
            $null = $db.Query("DROP PROCEDURE dbo.usp_Insertsomething")
            $null = $db.Query("DROP TYPE dbo.dbatools_tabletype")
        } catch {
            $null = 1
        }
        Remove-Item ".\hellorelative.sql" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    It "supports pipable instances" {
        $results = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Invoke-DbaQuery -Database tempdb -Query "Select 'hello' as TestColumn" -OutVariable "global:dbatoolsciOutput"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
    }
    It "supports parameters" {
        $sqlParams = @{ testvalue = 'hello' }
        $results = $TestConfig.InstanceMulti1 | Invoke-DbaQuery -Database tempdb -Query "Select @testvalue as TestColumn" -SqlParameters $sqlParams
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
    }
    It "supports AppendServerInstance" {
        $conn1 = Connect-DbaInstance $TestConfig.InstanceMulti1
        $conn2 = Connect-DbaInstance $TestConfig.InstanceMulti2
        $serverInstances = $conn1.Name, $conn2.Name
        $results = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Invoke-DbaQuery -Database tempdb -Query "Select 'hello' as TestColumn" -AppendServerInstance
        foreach ($result in $results) {
            $result.ServerInstance | Should -Not -Be Null
            $result.ServerInstance | Should -BeIn $serverInstances
        }
    }
    It "supports pipable databases" {
        $dbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database tempdb
        $results = $dbs | Invoke-DbaQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
        'tempdb' | Should -BeIn $results.dbname
    }
    It "stops when piped databases and -Database" {
        $dbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
        { $dbs | Invoke-DbaQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname" -Database tempdb -EnableException } | Should -Throw "You can't*"
    }
    It "supports reading files" {
        $testPath = "TestDrive:\dbasqlquerytest.txt"
        Set-Content $testPath -Value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -File $testPath
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
        'tempdb' | Should -BeIn $results.dbname
    }
    It "supports reading entire directories, just *.sql" {
        $testPath = "TestDrive:\"
        Set-Content "$testPath\dbasqlquerytest.sql" -Value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.sql" -Value "Select 'hello2' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.txt" -Value "Select 'hello3' as TestColumn, DB_NAME() as dbname"
        $pathinfo = Get-Item $testpath
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -File $pathinfo
        'hello' | Should -BeIn $results.TestColumn
        'hello2' | Should -BeIn $results.TestColumn
        'hello3' | Should -Not -BeIn $results.TestColumn
        'tempdb' | Should -BeIn $results.dbname

    }
    It "supports http files" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/dataplat/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -File $CloudQuery
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $check
        $results.Name | Should -Be 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $cleanup
    }
    It "supports smo objects" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/dataplat/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -File $CloudQuery
        $smoobj = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb | Where-Object Name -EQ 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database tempdb -SqlObject $smoobj
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database tempdb -Query $check
        $results.Name | Should -Be 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database tempdb -Query $cleanup
    }
    <#
    It "supports loose objects (with SqlInstance and database props)" {
        $dbs = Get-DbaDbState -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
        $results = $dbs | Invoke-DbaQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
    }    #>
    It "supports queries with GO statements" {
        $Query = @'
SELECT DB_NAME() as dbname
GO
SELECT @@servername as dbname
'@
        $results = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Invoke-DbaQuery -Database tempdb -Query $Query
        $results.dbname -contains 'tempdb' | Should -Be $true
    }
    It "streams correctly 'messages' with Verbose" {
        $query = @'
        DECLARE @time char(19)
        PRINT 'stmt_1|PRINT start|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_2|RAISERROR before WITHOUT NOWAIT|%s', 0, 1, @time)
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_3|PRINT after the first delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_4|RAISERROR with NOWAIT|%s', 0, 1, @time) WITH NOWAIT
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_5|PRINT after the second delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SELECT 'hello' AS TestColumn
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_6|PRINT end|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
'@
        $results = @()
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $query -Verbose 4>&1 | ForEach-Object {
            $results += [PSCustomObject]@{
                FiredAt = (Get-Date).ToUniversalTime()
                Out     = $PSItem
            }
        }
        $results.Length | Should -Be 7 # 6 'messages' plus the actual resultset
        ($results | ForEach-Object { Get-Date -Date $PSItem.FiredAt -Format s } | Get-Unique).Count | Should -Not -Be 1 # the first WITH NOWAIT (stmt_4) and after
        #($results[0..3]  | ForEach-Object { Get-Date -Date $PSItem.FiredAt -f s } | Get-Unique).Count | Should -Be 1 # everything before stmt_4 is fired at the same time
        #$parsedstmt_1 = Get-Date -Date $results[0].Out.Message.split('|')[2]
        #(Get-Date -Date (Get-Date -Date $parsedstmt_1).AddSeconds(3) -f s) | Should -Be (Get-Date -Date $results[0].FiredAt -f s) # stmt_1 is fired 3 seconds after the logged date
        #$parsedstmt_4 = Get-Date -Date $results[3].Out.Message.split('|')[2]
        #(Get-Date -Date (Get-Date -Date $parsedstmt_4) -f s) | Should -Be (Get-Date -Date $results[0].FiredAt -f s) # stmt_4 is fired at the same time the logged date is
    }
    It "streams correctly 'messages' with MessagesToOutput" {
        $query = @'
        DECLARE @time char(19)
        PRINT 'stmt_1|PRINT start|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_2|RAISERROR before WITHOUT NOWAIT|%s', 0, 1, @time)
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_3|PRINT after the first delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_4|RAISERROR with NOWAIT|%s', 0, 1, @time) WITH NOWAIT
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_5|PRINT after the second delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SELECT 'hello' AS TestColumn
        WAITFOR DELAY '00:00:01'
        PRINT 'stmt_6|PRINT end|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
'@
        $results = @()
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $query -MessagesToOutput | ForEach-Object {
            $results += [PSCustomObject]@{
                FiredAt = (Get-Date).ToUniversalTime()
                Out     = $PSItem
            }
        }
        $results.Length | Should -Be 7 # 6 'messages' plus the actual resultset
        ($results | ForEach-Object { Get-Date -Date $PSItem.FiredAt -Format s } | Get-Unique).Count | Should -Not -Be 1 # the first WITH NOWAIT (stmt_4) and after
    }
    It "Executes stored procedures with parameters" {
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "dbatoolsci_procedure_example" -SqlParameters @{ p1 = 1 } -CommandType StoredProcedure
        $results.TestColumn | Should -Be 1
    }
    It "Executes script file with a relative path (see #6184)" {
        Set-Content -Path ".\hellorelative.sql" -Value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -File ".\hellorelative.sql"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
        'tempdb' | Should -BeIn $results.dbname
    }
    It "supports multiple datatables also as array of PSObjects (see #6921)" {
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "select 1 as a union all select 2 union all select 3; select 4 as b, 5 as c union all select 6, 7;" -As PSObjectArray
        $results.Count | Should -Be 2
        $results[0].Count | Should -Be 3
        $results[0][0].a | Should -Be 1
        $results[1].Count | Should -Be 2
        $results[1][0].b | Should -Be 4
        $results[1][1].c | Should -Be 7
    }
    It "supports multiple datatables also as PSObjects (see #6921)" {
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "select 1 as a union all select 2 union all select 3; select 4 as b, 5 as c union all select 6, 7;" -As PSObject
        $results.Count | Should -Be 5
        $results[0].a | Should -Be 1
        $results[3].b | Should -Be 4
        $results[4].c | Should -Be 7
    }

    It "supports using SqlParameters as Microsoft.Data.SqlClient.SqlParameter (#7434)" {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "CREATE OR ALTER PROC [dbo].[my_proc]
                    @json_result nvarchar(max) output
                AS
                BEGIN
                set @json_result = (
                    select 'sample' as 'example'
                    for json path, without_array_wrapper
                );
                END"
        $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -CommandType StoredProcedure -Query my_proc -SqlParameters $output
        $output.Value | Should -Be '{"example":"sample"}'
    }

    It "supports using multiple and mixed params, even with different names (#7434)" {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "CREATE OR ALTER PROCEDURE usp_Insertsomething
    @somevalue varchar(10),
    @newid varchar(50) OUTPUT
        AS
        BEGIN
            SELECT 'fixedval' as somevalue, @somevalue as 'input param'
            SELECT @newid = '12345'
        END"
        $outparam = New-DbaSqlParameter -Direction Output -Size -1
        $sqlparams = @{
            'newid'     = $outparam
            'somevalue' = 'asd'
        }
        $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "EXEC usp_Insertsomething @somevalue, @newid output" -SqlParameters $sqlparams
        $outparam.Value | Should -Be '12345'
        $result.'input param' | Should -Be 'asd'
        $result.somevalue | Should -Be 'fixedval'
    }

    It "supports using the same parameters multiple times (#9217)" {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "CREATE OR ALTER PROCEDURE usp_Insertsomething
    @somevalue varchar(10),
    @newid varchar(50) OUTPUT
        AS
        BEGIN
            SELECT 'fixedval' as somevalue, @somevalue as 'input param'
            SELECT @newid = '12345'
        END"
        $inparam = New-DbaSqlParameter -ParameterName 'somevalue' -SqlDbType VarChar -Value 'example'
        $outparam = New-DbaSqlParameter -Direction Output -Size -1
        $sqlparams = @{
            'newid'     = $outparam
            'somevalue' = $inparam
        }
        $result1 = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "EXEC usp_Insertsomething @somevalue, @newid output" -SqlParameters $sqlparams
        $outparam.Value | Should -Be '12345'
        $result1.'input param' | Should -Be 'example'
        $result1.somevalue | Should -Be 'fixedval'

        $result2 = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "EXEC usp_Insertsomething @somevalue, @newid output" -SqlParameters $sqlparams
        $outparam.Value | Should -Be '12345'
        $result2.'input param' | Should -Be 'example'
        $result2.somevalue | Should -Be 'fixedval'
    }

    It "supports complex types, such as datatables (#7434)" {
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "
IF NOT EXISTS (SELECT * FROM sys.types WHERE name = N'dbatools_tabletype')
CREATE TYPE dbatools_tabletype AS TABLE(
    somestring varchar(50),
    somedate datetime2(7)
)
GO
CREATE OR ALTER PROCEDURE usp_Insertsomething
    @sometable dbatools_tabletype READONLY,
    @newid varchar(50) OUTPUT
AS
BEGIN
    SELECT * FROM @sometable ORDER BY somestring
    SELECT @newid = '12345'
END"
        $outparam = New-DbaSqlParameter -Direction Output -Size -1
        $inparam = @()
        $inparam += [PSCustomObject]@{
            somestring = 'string1'
            somedate   = '2021-07-15T01:02:00'
        }
        $inparam += [PSCustomObject]@{
            somestring = 'string2'
            somedate   = '2021-07-15T02:03:00'
        }
        $sqlparams = @{
            'newid'     = $outparam
            'sometable' = New-DbaSqlParameter -SqlDbType structured -Value (ConvertTo-DbaDataTable -InputObject $inparam) -TypeName 'dbatools_tabletype'
        }
        $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "EXEC usp_Insertsomething @sometable, @newid output" -SqlParameters $sqlparams
        $outparam.Value | Should -Be '12345'
        $result.Count | Should -Be 2
        $result[0].somestring | Should -Be 'string1'
        (Get-Date -Date $result[1].somedate -f 'yyyy-MM-ddTHH:mm:ss') | Should -Be '2021-07-15T02:03:00'
    }

    It "support NOEXEC mode" {
        $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT 1" -NoExec
        $result | Should -BeNullOrEmpty
        #for multiple batches, too
        $q = @'
SELECT 1
GO
SELECT 2
'@
        $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $q -NoExec
        $result | Should -BeNullOrEmpty

        { Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELEC p FROM c" -NoExec -EnableException } | Should -Throw "Incorrect syntax near 'SELEC'."
    }

    It "supports QuotedIdentifier for filtered index compatibility" {
        # Create table with filtered index that requires QUOTED_IDENTIFIER ON
        $tableName = "dbatoolsci_TestFiltered_$(Get-Random)"
        $setupQuery = @"
IF OBJECT_ID('tempdb.dbo.$tableName') IS NOT NULL DROP TABLE dbo.$tableName;
CREATE TABLE dbo.$tableName (Id INT PRIMARY KEY, Name VARCHAR(100), IsDeleted BIT DEFAULT 0);
CREATE INDEX IX_Filtered ON dbo.$tableName(Name) WHERE IsDeleted = 0;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $setupQuery

        # Insert with QuotedIdentifier should succeed
        $splatInsert = @{
            SqlInstance      = $TestConfig.InstanceMulti1
            Database         = "tempdb"
            Query            = "INSERT INTO dbo.$tableName (Id, Name) VALUES (1, 'Test'); SELECT COUNT(*) as cnt FROM dbo.$tableName;"
            QuotedIdentifier = $true
        }
        $result = Invoke-DbaQuery @splatInsert
        $result.cnt | Should -Be 1

        # Cleanup
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "DROP TABLE dbo.$tableName"
    }

    It "supports dropping temp objects (#8472)" {
        $sql = "CREATE PROC #DropStatistics
                AS
                SELECT 1
                GO
                drop procedure #DropStatistics
                go"
        { Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $sql -EnableException } | Should -Not -Throw
    }

    It "supports geography types (#8541)" {
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "select cast(null as geometry)"
        $results.Column1 | Should -Be "Null"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "select cast(null as geography)"
        $results.Column1 | Should -Be "Null"
        $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "select cast(null as hierarchyid)"
        $results.Column1 | Should -Be "NULL"
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}