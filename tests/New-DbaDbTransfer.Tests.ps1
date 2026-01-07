#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbTransfer",
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbName = "dbatools_transfer"
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $source.Query("CREATE DATABASE $dbName")
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
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

        $allowedObjects = @(
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
        $creds = New-Object PSCredential ("foo", $securePassword)
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
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
    }

    Context "Testing connection parameters" {
        It "Should create a transfer object" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
            $transfer | Should -BeOfType Microsoft.SqlServer.Management.Smo.Transfer
            $transfer.BatchSize | Should -Be 50000
            $transfer.BulkCopyTimeout | Should -Be 5000
            $transfer.Database.Name | Should -Be $dbName
            @($transfer.ObjectList) | Should -BeNullOrEmpty
            $transfer.CopyAllObjects | Should -Be $false
            $allowedObjects | ForEach-Object { @($transfer.($_.ToString())) | Should -BeNullOrEmpty }
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $transfer.DestinationDatabase | Should -Be $dbName
            $transfer.DestinationServer | Should -BeNullOrEmpty
        }

        It "Should properly assign dest server parameters from full connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -DestinationSqlInstance "Data Source=foo;User=bar;password=foobar;Initial Catalog=hog"
            $transfer.DestinationDatabase | Should -Be hog
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be bar
            $transfer.DestinationPassword | Should -Be foobar
            $transfer.DestinationServer | Should -Be foo
        }

        It "Should properly assign dest server parameters from trusted connstring" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -DestinationSqlInstance "Data Source=foo;Integrated Security=True"
            $transfer.DestinationDatabase | Should -Be $dbName
            $transfer.DestinationLoginSecure | Should -Be $true
            $transfer.DestinationLogin | Should -BeNullOrEmpty
            $transfer.DestinationPassword | Should -BeNullOrEmpty
            $transfer.DestinationServer | Should -Be foo
        }

        It "Should properly assign dest server parameters from server object" {
            $dest = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2 -Database msdb
            $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $dest.ConnectionContext.ConnectionString
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -DestinationSqlInstance $dest
            $transfer.DestinationDatabase | Should -Be $connStringBuilder["Initial Catalog"]
            $transfer.DestinationLoginSecure | Should -Be $connStringBuilder["Integrated Security"]
            $transfer.DestinationLogin | Should -Be $connStringBuilder["User ID"]
            $transfer.DestinationPassword | Should -Be $connStringBuilder["Password"]
            $transfer.DestinationServer | Should -Be $connStringBuilder["Data Source"]
        }

        It "Should properly assign dest server parameters from plaintext params" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -DestinationSqlInstance foo -DestinationDatabase bar -DestinationSqlCredential $creds
            $transfer.DestinationDatabase | Should -Be bar
            $transfer.DestinationLoginSecure | Should -Be $false
            $transfer.DestinationLogin | Should -Be $creds.UserName
            $transfer.DestinationPassword | Should -Be $creds.GetNetworkCredential().Password
            $transfer.DestinationServer | Should -Be foo
        }
    }

    Context "Testing function parameters" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -CopyAllObjects
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should script all tables with just schemas" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -CopyAll Tables -SchemaOnly
            $transfer.CopyData | Should -Be $false
            $transfer.CopySchema | Should -Be $true
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should script one table with just data" {
            $table = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -Table transfer_test
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -InputObject $table -DataOnly
            $transfer.ObjectList.Count | Should -Be 1
            $transfer.CopyData | Should -Be $true
            $transfer.CopySchema | Should -Be $false
            # # data only ScriptTransfer still creates schema
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }

        It "Should script two tables from pipeline" {
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -Table transfer_test2, transfer_test4
            $transfer = $tables | New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
            $transfer.ObjectList.Count | Should -Be 2
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -Not -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }

        It "Should accept script options object" {
            $options = New-DbaScriptingOption
            $options.ScriptDrops = $true
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -CopyAll Tables -ScriptingOption $options
            $transfer.Options.ScriptDrops | Should -BeTrue
            $script = $transfer.ScriptTransfer() -join "`n"
            $script | Should -BeLike '*DROP TABLE `[dbo`].`[transfer_test`]*'
        }
    }

    Context "Testing object transfer" {
        BeforeEach {
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName
        }

        AfterEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName
        }

        It "Should transfer all tables" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -DestinationSqlInstance $TestConfig.InstanceMulti2 -Database $dbName -CopyAll Tables
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
        }

        It "Should transfer two tables with just schemas" {
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -DestinationSqlInstance $TestConfig.InstanceMulti2 -Database $dbName -SchemaOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            @($db2.Query("select id from dbo.transfer_test").id) | Should -BeNullOrEmpty
        }

        It "Should transfer two tables without copying schema" {
            $null = $db2.Query("CREATE TABLE dbo.transfer_test (id int)")
            $null = $db2.Query("CREATE TABLE dbo.transfer_test2 (id int)")
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -DestinationSqlInstance $TestConfig.InstanceMulti2 -Database $dbName -DataOnly
            $transfer.TransferData()
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
        }
    }
}