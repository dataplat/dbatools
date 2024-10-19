param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbTransfer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbName = 'dbatools_transfer'
        $source = Connect-DbaInstance -SqlInstance $global:instance2
        $destination = Connect-DbaInstance -SqlInstance $global:instance3
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbName -Confirm:$false
        $source.Query("CREATE DATABASE $dbName")
        $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbName
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
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbName -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbTransfer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have DestinationSqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlInstance
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have DestinationDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationDatabase
        }
        It "Should have BatchSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize
        }
        It "Should have BulkCopyTimeOut as a parameter" {
            $CommandUnderTest | Should -HaveParameter BulkCopyTimeOut
        }
        It "Should have ScriptingOption as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptingOption
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have CopyAllObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CopyAllObjects
        }
        It "Should have CopyAll as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyAll
        }
        It "Should have SchemaOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SchemaOnly
        }
        It "Should have DataOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DataOnly
        }
        It "Should have ScriptOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptOnly
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $global:instance2 -Database $dbName -CopyAllObjects
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script all tables with schema only" {
            $scripts = Invoke-DbaDbTransfer -SqlInstance $global:instance2 -Database $dbName -CopyAll Tables -SchemaOnly -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
    }

    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $global:instance3 -Database $dbName -Confirm:$false
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbName
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance3 -Database $dbName -Confirm:$false
        }
        It "Should transfer all tables" {
            $result = Invoke-DbaDbTransfer -SqlInstance $global:instance2 -DestinationSqlInstance $global:instance3 -Database $dbName -CopyAll Tables
            $tables = Get-DbaDbTable -SqlInstance $global:instance3 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $global:instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $global:instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
        It "Should transfer select tables piping the transfer object" {
            $sourceTables = Get-DbaDbTable -SqlInstance $global:instance2 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $global:instance2 -DestinationSqlInstance $global:instance3 -Database $dbName
            $result = $transfer | Invoke-DbaDbTransfer
            $tables = Get-DbaDbTable -SqlInstance $global:instance3 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $global:instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $global:instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
    }
}
