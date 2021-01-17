$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'DestinationSqlInstance', 'DestinationSqlCredential', 'Database', 'DestinationDatabase', 'BatchSize', 'BulkCopyTimeOut', 'InputObject', 'EnableException', 'CopyAllObjects', 'CopyAll', 'SchemaOnly', 'DataOnly', 'ScriptingOption', 'ScriptOnly'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbName = 'dbatools_transfer'
        $source = Connect-DbaInstance -SqlInstance $script:instance2
        $destination = Connect-DbaInstance -SqlInstance $script:instance3
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbName -Confirm:$false
        $source.Query("CREATE DATABASE $dbName")
        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbName
        $null = $db.Query("CREATE TABLE dbo.transfer_test (id int);
            INSERT dbo.transfer_test
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.transfer_test2 (id int)")
        $null = $db.Query("CREATE TABLE dbo.transfer_test3 (id int)")
        $null = $db.Query("CREATE TABLE dbo.transfer_test4 (id int);
            INSERT dbo.transfer_test4
            SELECT top 13 1
            FROM sys.objects")
        $securePassword = 'bar' | ConvertTo-SecureString -AsPlainText -Force
        $creds = New-Object PSCredential ('foo', $securePassword)
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.transfer_test")
            $null = $db.Query("DROP TABLE dbo.transfer_test2")
            $null = $db.Query("DROP TABLE dbo.transfer_test3")
            $null = $db.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbName -Confirm:$false
    }
    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $script:instance2 -Database $dbName -CopyAllObjects
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script all tables with schema only" {
            $scripts = Invoke-DbaDbTransfer -SqlInstance $script:instance2 -Database $dbName -CopyAll Tables -SchemaOnly -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
    }
    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $script:instance3 -Database $dbName -Confirm:$false
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbName
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance3 -Database $dbName -Confirm:$false
        }
        It "Should transfer all tables" {
            $result = Invoke-DbaDbTransfer -SqlInstance $script:instance2 -DestinationSqlInstance $script:instance3 -Database $dbName -CopyAll Tables
            $tables = Get-DbaDbTable -SqlInstance $script:instance3 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $script:instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $script:instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
        It "Should transfer select tables piping the transfer object" {
            $sourceTables = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $script:instance2 -DestinationSqlInstance $script:instance3 -Database $dbName
            $result = $transfer | Invoke-DbaDbTransfer
            $tables = Get-DbaDbTable -SqlInstance $script:instance3 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $script:instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $script:instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
    }
}