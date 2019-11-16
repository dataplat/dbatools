$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Query', 'QueryTimeout', 'File', 'SqlObject', 'As', 'SqlParameters', 'AppendServerInstance', 'MessagesToOutput', 'InputObject', 'ReadOnly', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate alias" {
        It "Should contain the alias: ivq" {
            (Get-Alias ivq) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    It "supports pipable instances" {
        $results = $script:instance2, $script:instance3 | Invoke-DbaQuery -Database tempdb -Query "Select 'hello' as TestColumn"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
    }
    It "supports parameters" {
        $sqlParams = @{ testvalue = 'hello' }
        $results = $script:instance2 | Invoke-DbaQuery -Database tempdb -Query "Select @testvalue as TestColumn" -SqlParameters $sqlParams
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
    }
    It "supports AppendServerInstance" {
        $conn1 = Connect-DbaInstance $script:instance2
        $conn2 = Connect-DbaInstance $script:instance3
        $serverInstances = $conn1.Name, $conn2.Name
        $results = $script:instance2, $script:instance3 | Invoke-DbaQuery -Database tempdb -Query "Select 'hello' as TestColumn" -AppendServerInstance
        foreach ($result in $results) {
            $result.ServerInstance | Should -Not -Be Null
            $result.ServerInstance | Should -BeIn $serverInstances
        }
    }
    It "supports pipable databases" {
        $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3
        $results = $dbs | Invoke-DbaQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
        'tempdb' | Should -Bein $results.dbname
    }
    It "stops when piped databases and -Database" {
        $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3
        { $dbs | Invoke-DbaQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname" -Database tempdb -EnableException } | Should Throw "You can't"
    }
    It "supports reading files" {
        $testPath = "TestDrive:\dbasqlquerytest.txt"
        Set-Content $testPath -value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -File $testPath
        foreach ($result in $results) {
            $result.TestColumn | Should -Be 'hello'
        }
        'tempdb' | Should -Bein $results.dbname
    }
    It "supports reading entire directories, just *.sql" {
        $testPath = "TestDrive:\"
        Set-Content "$testPath\dbasqlquerytest.sql" -value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.sql" -value "Select 'hello2' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.txt" -value "Select 'hello3' as TestColumn, DB_NAME() as dbname"
        $pathinfo = Get-Item $testpath
        $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -File $pathinfo
        'hello' | Should -Bein $results.TestColumn
        'hello2' | Should -Bein $results.TestColumn
        'hello3' | Should -Not -Bein $results.TestColumn
        'tempdb' | Should -Bein $results.dbname

    }
    It "supports http files" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/sqlcollaborative/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -File $CloudQuery
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $check
        $results.Name | Should -Be 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $cleanup
    }
    It "supports smo objects" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaQuery -SqlInstance $script:instance2, $script:instance3 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/sqlcollaborative/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -File $CloudQuery
        $smoobj = Get-DbaDbTable -SqlInstance $script:instance2 -Database tempdb | Where-Object Name -eq 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $script:instance3 -Database tempdb -SqlObject $smoobj
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaQuery -SqlInstance $script:instance3 -Database tempdb -Query $check
        $results.Name | Should Be 'CommandLog'
        $null = Invoke-DbaQuery -SqlInstance $script:instance2, $script:instance3 -Database tempdb -Query $cleanup
    }
    <#
    It "supports loose objects (with SqlInstance and database props)" {
        $dbs = Get-DbaDbState -SqlInstance $script:instance2, $script:instance3
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
        $results = $script:instance2, $script:instance3 | Invoke-DbaQuery -Database tempdb -Query $Query
        $results.dbname -contains 'tempdb' | Should -Be $true
    }
    It "streams correctly 'messages' with Verbose" {
        $query = @'
        DECLARE @time char(19)
        PRINT 'stmt_1|PRINT start|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_2|RAISERROR before WITHOUT NOWAIT|%s', 0, 1, @time)
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_3|PRINT after the first delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_4|RAISERROR with NOWAIT|%s', 0, 1, @time) WITH NOWAIT
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_5|PRINT after the second delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SELECT 'hello' AS TestColumn
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_6|PRINT end|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
'@
        $results = @()
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $query -Verbose 4>&1 | ForEach-Object {
            $results += [pscustomobject]@{
                FiredAt = (Get-Date).ToUniversalTime()
                Out     = $_
            }
        }
        $results.Length | Should -Be 7 # 6 'messages' plus the actual resultset
        ($results | ForEach-Object { Get-Date -Date $_.FiredAt -Format s } | Get-Unique).Count | Should -Not -Be 1 # the first WITH NOWAIT (stmt_4) and after
        #($results[0..3]  | ForEach-Object { Get-Date -Date $_.FiredAt -f s } | Get-Unique).Count | Should -Be 1 # everything before stmt_4 is fired at the same time
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
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_3|PRINT after the first delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SET @time= CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        RAISERROR ('stmt_4|RAISERROR with NOWAIT|%s', 0, 1, @time) WITH NOWAIT
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_5|PRINT after the second delay|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
        SELECT 'hello' AS TestColumn
        WAITFOR DELAY '00:00:03'
        PRINT 'stmt_6|PRINT end|' + CONVERT(VARCHAR(19), GETUTCDATE(), 126)
'@
        $results = @()
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $query -MessagesToOutput | ForEach-Object {
            $results += [pscustomobject]@{
                FiredAt = (Get-Date).ToUniversalTime()
                Out     = $_
            }
        }
        $results.Length | Should -Be 7 # 6 'messages' plus the actual resultset
        ($results | ForEach-Object { Get-Date -Date $_.FiredAt -Format s } | Get-Unique).Count | Should -Not -Be 1 # the first WITH NOWAIT (stmt_4) and after
    }
}