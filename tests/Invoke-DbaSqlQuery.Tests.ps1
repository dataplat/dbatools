$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    It "supports pipable instances" {
        $results = $script:instance1, $script:instance2 | Invoke-DbaSqlQuery -Database tempdb -Query "Select 'hello' as TestColumn"
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
    }
    It "supports parameters" {
        $sqlParams = @{testvalue = 'hello'}
        $results = $script:instance1 | Invoke-DbaSqlQuery -Database tempdb -Query "Select @testvalue as TestColumn" -SqlParameters $sqlParams
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
    }
    It "supports AppendServerInstance" {
        $results = $script:instance1, $script:instance2 | Invoke-DbaSqlQuery -Database tempdb -Query "Select 'hello' as TestColumn" -AppendServerInstance
        foreach ($result in $results) {
            $result.ServerInstance | Should Not Be Null
        }
    }
    It "supports pipable databases" {
        $dbs = Get-DbaDatabase -SqlInstance $script:instance1, $script:instance2
        $results = $dbs | Invoke-DbaSqlQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
        'tempdb' | Should -Bein $results.dbname
    }
    It "stops when piped databases and -Database" {
        $dbs = Get-DbaDatabase -SqlInstance $script:instance1, $script:instance2
        { $dbs | Invoke-DbaSqlQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname" -Database tempdb -EnableException } | Should Throw "You can't"
    }
    It "supports reading files" {
        $testPath = "TestDrive:\dbasqlquerytest.txt"
        Set-Content $testPath -value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        $results = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -File $testPath
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
        'tempdb' | Should -Bein $results.dbname
    }
    It "supports reading entire directories, just *.sql" {
        $testPath = "TestDrive:\"
        Set-Content "$testPath\dbasqlquerytest.sql" -value "Select 'hello' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.sql" -value "Select 'hello2' as TestColumn, DB_NAME() as dbname"
        Set-Content "$testPath\dbasqlquerytest2.txt" -value "Select 'hello3' as TestColumn, DB_NAME() as dbname"
        $pathinfo = Get-Item $testpath
        $results = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -File $pathinfo
        'hello' | Should -Bein $results.TestColumn
        'hello2' | Should -Bein $results.TestColumn
        'hello3' | Should -Not -Bein $results.TestColumn
        'tempdb' | Should -Bein $results.dbname

    }
    It "supports http files" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/sqlcollaborative/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -File $CloudQuery
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -Query $check
        $results.Name | Should Be 'CommandLog'
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -Query $cleanup
    }
    It "supports smo objects" {
        $cleanup = "IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')) DROP TABLE [dbo].[CommandLog]"
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1, $script:instance2 -Database tempdb -Query $cleanup
        $CloudQuery = 'https://raw.githubusercontent.com/sqlcollaborative/appveyor-lab/master/sql2016-startup/ola/CommandLog.sql'
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1 -Database tempdb -File $CloudQuery
        $smoobj = Get-Dbatable -SqlInstance $script:instance1 -Database tempdb  | Where-Object Name -eq 'CommandLog'
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Database tempdb -SqlObject $smoobj
        $check = "SELECT name FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CommandLog]') AND type in (N'U')"
        $results = Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Database tempdb -Query $check
        $results.Name | Should Be 'CommandLog'
        $null = Invoke-DbaSqlQuery -SqlInstance $script:instance1, $script:instance2 -Database tempdb -Query $cleanup
    }
    <#
    It "supports loose objects (with SqlInstance and database props)" {
        $dbs = Get-DbaDatabaseState -SqlInstance $script:instance1, $script:instance2
        $results = $dbs | Invoke-DbaSqlQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
    }#>
    It "supports queries with GO statements" {
        $Query = @'
SELECT DB_NAME() as dbname
GO
SELECT @@servername as dbname
'@
        $results = $script:instance1, $script:instance2 | Invoke-DbaSqlQuery -Database tempdb -Query $Query
        $results.dbname -contains 'tempdb' | Should Be $true
    }
}