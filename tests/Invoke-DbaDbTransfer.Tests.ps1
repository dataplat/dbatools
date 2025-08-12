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
                "InputObject",
                "EnableException",
                "CopyAllObjects",
                "CopyAll",
                "SchemaOnly",
                "DataOnly",
                "ScriptingOption",
                "ScriptOnly"
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "dbatools_transfer"
        $sourceInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $destinationInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false
        $sourceInstance.Query("CREATE DATABASE $dbName")
        $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName
        $null = $sourceDb.Query("CREATE TABLE dbo.transfer_test (id int);
            INSERT dbo.transfer_test
            SELECT top 10 1
            FROM sys.objects")
        $null = $sourceDb.Query("CREATE TABLE dbo.transfer_test2 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.transfer_test3 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.transfer_test4 (id int);
            INSERT dbo.transfer_test4
            SELECT top 13 1
            FROM sys.objects")
        $securePassword = "bar" | ConvertTo-SecureString -AsPlainText -Force
        $testCreds = New-Object PSCredential ("foo", $securePassword)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $null = $sourceDb.Query("DROP TABLE dbo.transfer_test")
            $null = $sourceDb.Query("DROP TABLE dbo.transfer_test2")
            $null = $sourceDb.Query("DROP TABLE dbo.transfer_test3")
            $null = $sourceDb.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false
    }

    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance2 -Database $dbName -CopyAllObjects
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }

        It "Should script all tables with schema only" {
            $scripts = Invoke-DbaDbTransfer -SqlInstance $TestConfig.instance2 -Database $dbName -CopyAll Tables -SchemaOnly -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
    }

    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Confirm:$false
            $destinationInstance.Query("CREATE DATABASE $dbname")
            $destinationDb = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName
        }

        AfterEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should transfer all tables" {
            $result = Invoke-DbaDbTransfer -SqlInstance $TestConfig.instance2 -DestinationSqlInstance $TestConfig.instance3 -Database $dbName -CopyAll Tables
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance3 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $sourceDb.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $sourceDb.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $sourceDb.Query("select id from dbo.transfer_test").id | Should -BeIn $destinationDb.Query("select id from dbo.transfer_test").id
            $sourceDb.Query("select id from dbo.transfer_test4").id | Should -BeIn $destinationDb.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $TestConfig.instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be "Success"
            $result.Log -join "`n" | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
        }

        It "Should transfer select tables piping the transfer object" {
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.instance2 -DestinationSqlInstance $TestConfig.instance3 -Database $dbName
            $result = $transfer | Invoke-DbaDbTransfer
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance3 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $sourceDb.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $sourceDb.Query("select id from dbo.transfer_test").id | Should -BeIn $destinationDb.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $TestConfig.instance2
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.instance3
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be "Success"
            $result.Log -join "`n" | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
        }
    }
}