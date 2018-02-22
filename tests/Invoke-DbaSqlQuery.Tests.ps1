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
    }
    It "stops when piped databases and -Database" {
        $dbs = Get-DbaDatabaseState -SqlInstance $script:instance1, $script:instance2
        { $dbs | Invoke-DbaSqlQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname" -Database tempdb -EnableException } | Should Throw "You can't"
    }
    It "supports loose objects (with SqlInstance and database props)" {
        $dbs = Get-DbaDatabaseState -SqlInstance $script:instance1, $script:instance2
        $results = $dbs | Invoke-DbaSqlQuery -Query "Select 'hello' as TestColumn, DB_NAME() as dbname"
        foreach ($result in $results) {
            $result.TestColumn | Should Be 'hello'
        }
    }
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