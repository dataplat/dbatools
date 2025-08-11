#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaDbTransfer",
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
                "ScriptingOption"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $global:dbName = "dbatools_transfer"
        $global:source = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $global:destination = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:source.Query("CREATE DATABASE $global:dbName")
        $global:db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:dbName
        $null = $global:db.Query("CREATE TABLE dbo.transfer_test (id int);
            INSERT dbo.transfer_test
            SELECT top 10 1
            FROM sys.objects")
        $null = $global:db.Query("CREATE TABLE dbo.transfer_test2 (id int)")
        $null = $global:db.Query("CREATE TABLE dbo.transfer_test3 (id int)")
        $null = $global:db.Query("CREATE TABLE dbo.transfer_test4 (id int);
            INSERT dbo.transfer_test4
            SELECT top 13 1
            FROM sys.objects")

        $global:allowedObjects = @(
            "FullTextCatalogs",
            "FullTextStopLists",
            "SearchPropertyLists",
            "Tables",
            "Views",
            "StoredProcedures",
            "UserDefinedFunctions",
            "UserDefinedDataTypes",
            "UserDefinedTableTypes",
            "PlanGuides",
            "Rules",
            "Defaults",
            "Users",
            "Roles",
            "PartitionSchemes",
            "PartitionFunctions",
            "XmlSchemaCollections",
            "SqlAssemblies",
            "UserDefinedAggregates",
            "UserDefinedTypes",
            "Schemas",
            "Synonyms",
            "Sequences",
            "DatabaseTriggers",
            "DatabaseScopedCredentials",
            "ExternalFileFormats",
            "ExternalDataSources",
            "Logins",
            "ExternalLibraries"
        )
        $securePassword = "bar" | ConvertTo-SecureString -AsPlainText -Force
        $global:creds = New-Object PSCredential ("foo", $securePassword)
    }
    AfterAll {
        try {
            $null = $global:db.Query("DROP TABLE dbo.transfer_test")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test2")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test3")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue
    }
    Context "Testing connection parameters" {
        It "Should create a transfer object" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName
            $transfer | Should -BeOfType Microsoft.SqlServer.Management.Smo.Transfer
            $transfer.BatchSize | Should -Be 50000
            $transfer.BulkCopyTimeout | Should -Be 5000
            $transfer.Database.Name | Should -Be $global:dbName
            $transfer.ObjectList | Should -BeNullOrEmpty
            $transfer.CopyAllObjects | Should -Be $false
            $global:allowedObjects | ForEach-Object { $transfer.$_ | Should -BeNullOrEmpty }
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $transfer.DestinationDatabase | Should -Be $global:dbName
            $transfer.DestinationServer | Should -BeNullOrEmpty
        }
        It "Should properly assign dest server parameters from full connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -DestinationSqlInstance "Data Source=foo;User=bar;password=foobar;Initial Catalog=hog"
            $transfer.DestinationDatabase | Should -Be hog
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be bar
            $transfer.DestinationPassword | Should -Be foobar
            $transfer.DestinationServer | Should -Be foo
        }
        It "Should properly assign dest server parameters from trusted connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -DestinationSqlInstance "Data Source=foo;Integrated Security=True"
            $transfer.DestinationDatabase | Should -Be $global:dbName
            $transfer.DestinationLoginSecure | Should -Be $true
            $transfer.DestinationLogin | Should -BeNullOrEmpty
            $transfer.DestinationPassword | Should -BeNullOrEmpty
            $transfer.DestinationServer | Should -Be foo
        }
        It "Should properly assign dest server parameters from server object" {
            $dest = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database msdb
            $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $dest.ConnectionContext.ConnectionString
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -DestinationSqlInstance $dest
            $transfer.DestinationDatabase | Should -Be $connStringBuilder["Initial Catalog"]
            $transfer.DestinationLoginSecure | Should -Be $connStringBuilder["Integrated Security"]
            $transfer.DestinationLogin | Should -Be $connStringBuilder["User ID"]
            $transfer.DestinationPassword | Should -Be $connStringBuilder["Password"]
            $transfer.DestinationServer | Should -Be $connStringBuilder["Data Source"]
        }
        It "Should properly assign dest server parameters from plaintext params" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -DestinationSqlInstance foo -DestinationDatabase bar -DestinationSqlCredential $global:creds
            $transfer.DestinationDatabase | Should -Be bar
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be $global:creds.UserName
            $transfer.DestinationPassword | Should -Be $global:creds.GetNetworkCredential().Password
            $transfer.DestinationServer | Should -Be foo
        }
    }
    Context "Testing function parameters" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -CopyAllObjects
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
        It "Should script all tables with just schemas" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -CopyAll Tables -SchemaOnly
            $transfer.CopyData | Should -Be $false
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
        It "Should script one table with just data" {
            $table = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $global:dbName -Table transfer_test
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -InputObject $table -DataOnly
            $transfer.ObjectList.Count | Should -Be 1
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $false
            # # data only ScriptTransfer still creates schema
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
        }
        It "Should script two tables from pipeline" {
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $global:dbName -Table transfer_test2, transfer_test4
            $transfer = $tables | New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName
            $transfer.ObjectList.Count | Should -Be 2
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -Not -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -Not -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
        It "Should accept script options object" {
            $options = New-DbaScriptingOption
            $options.ScriptDrops = $true
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -Database $global:dbName -CopyAll Tables -ScriptingOption $options
            $transfer.Options.ScriptDrops | Should -BeTrue
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike "*DROP TABLE `[dbo`].`[transfer_test`]*"
        }
    }
    Context "Testing object transfer" {
        BeforeEach {
            $global:destination.Query("CREATE DATABASE $global:dbName")
            $global:db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbName
        }
        AfterEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue
        }
        It "Should transfer all tables" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -DestinationSqlInstance $TestConfig.instance2 -Database $global:dbName -CopyAll Tables
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $global:dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $global:db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test").id
            $global:db.Query("select id from dbo.transfer_test4").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test4").id
        }
        It "Should transfer two tables with just schemas" {
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $global:dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -DestinationSqlInstance $TestConfig.instance2 -Database $global:dbName -SchemaOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $global:dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $global:db2.Query("select id from dbo.transfer_test").id | Should -BeNullOrEmpty
        }
        It "Should transfer two tables without copying schema" {
            $null = $global:db2.Query("CREATE TABLE dbo.transfer_test (id int)")
            $null = $global:db2.Query("CREATE TABLE dbo.transfer_test2 (id int)")
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $global:dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.instance1 -DestinationSqlInstance $TestConfig.instance2 -Database $global:dbName -DataOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $global:dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $global:db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test").id
        }
    }
}