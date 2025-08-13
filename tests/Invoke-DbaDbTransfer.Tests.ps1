#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbTransfer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "DestinationSqlInstance",
                "DestinationSqlCredential",
                "Database",
                "DestinationDatabase",
                "BatchSize",
                "BulkCopyTimeOut",
                "ScriptingOption",
                "InputObject",
                "CopyAllObjects",
                "CopyAll",
                "SchemaOnly",
                "DataOnly",
                "ScriptOnly",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables. They are available in all the It blocks.
        $dbName = "dbatools_transfer"
        $source = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false
        $source.Query("CREATE DATABASE $dbName")
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName
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
        $securePassword = "bar" | ConvertTo-SecureString -AsPlainText -Force
        $creds = New-Object PSCredential ("foo", $securePassword)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        try {
            $null = $db.Query("DROP TABLE dbo.transfer_test")
            $null = $db.Query("DROP TABLE dbo.transfer_test2")
            $null = $db.Query("DROP TABLE dbo.transfer_test3")
            $null = $db.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $splatTransfer = @{
                SqlInstance    = $TestConfig.instance2
                Database       = $dbName
                CopyAllObjects = $true
            }
            $transfer = New-DbaDbTransfer @splatTransfer
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script all tables with schema only" {
            $splatScript = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                CopyAll     = "Tables"
                SchemaOnly  = $true
                ScriptOnly  = $true
            }
            $scripts = Invoke-DbaDbTransfer @splatScript
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
    }
    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Confirm:$false
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        }
        It "Should transfer all tables" {
            $splatInvoke = @{
                SqlInstance            = $TestConfig.instance2
                DestinationSqlInstance = $TestConfig.instance3
                Database               = $dbName
                CopyAll                = "Tables"
            }
            $result = Invoke-DbaDbTransfer @splatInvoke
            $splatGetTable = @{
                SqlInstance = $TestConfig.instance3
                Database    = $dbName
                Table       = "transfer_test", "transfer_test2", "transfer_test3", "transfer_test4"
            }
            $tables = Get-DbaDbTable @splatGetTable
            $tables.Status.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $TestConfig.instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
        It "Should transfer select tables piping the transfer object" {
            $splatSourceTables = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Table       = "transfer_test", "transfer_test2"
            }
            $sourceTables = Get-DbaDbTable @splatSourceTables
            $splatNewTransfer = @{
                SqlInstance            = $TestConfig.instance2
                DestinationSqlInstance = $TestConfig.instance3
                Database               = $dbName
            }
            $transfer = $sourceTables | New-DbaDbTransfer @splatNewTransfer
            $result = $transfer | Invoke-DbaDbTransfer
            $splatGetTable2 = @{
                SqlInstance = $TestConfig.instance3
                Database    = $dbName
                Table       = "transfer_test", "transfer_test2"
            }
            $tables = Get-DbaDbTable @splatGetTable2
            $tables.Status.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $TestConfig.instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
    }
}
