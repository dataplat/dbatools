#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbTransfer",
    $PSDefaultParameterValues = (Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = (Get-TestConfig).CommonParameters
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

        $global:dbName = "dbatools_transfer"
        $global:testConfig = Get-TestConfig
        
        $splatSource = @{
            SqlInstance     = $global:testConfig.instance2
            EnableException = $true
        }
        $global:source = Connect-DbaInstance @splatSource
        
        $splatDestination = @{
            SqlInstance     = $global:testConfig.instance3
            EnableException = $true
        }
        $global:destination = Connect-DbaInstance @splatDestination
        
        Remove-DbaDatabase -SqlInstance $global:testConfig.instance2 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue
        $global:source.Query("CREATE DATABASE $global:dbName")
        $global:db = Get-DbaDatabase -SqlInstance $global:testConfig.instance2 -Database $global:dbName
        
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
        
        $securePassword = "bar" | ConvertTo-SecureString -AsPlainText -Force
        $global:creds = New-Object PSCredential ("foo", $securePassword)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        try {
            $null = $global:db.Query("DROP TABLE dbo.transfer_test")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test2")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test3")
            $null = $global:db.Query("DROP TABLE dbo.transfer_test4")
        } catch {
            $null = 1
        }
        Remove-DbaDatabase -SqlInstance $global:testConfig.instance2 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $global:testConfig.instance2 -Database $global:dbName -CopyAllObjects
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
        It "Should script all tables with schema only" {
            $scripts = Invoke-DbaDbTransfer -SqlInstance $global:testConfig.instance2 -Database $global:dbName -CopyAll Tables -SchemaOnly -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test2`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test3`]*"
            $script | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test4`]*"
        }
    }
    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $global:testConfig.instance3 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue
            $global:destination.Query("CREATE DATABASE $global:dbName")
            $global:db2 = Get-DbaDatabase -SqlInstance $global:testConfig.instance3 -Database $global:dbName
        }
        AfterEach {
            Remove-DbaDatabase -SqlInstance $global:testConfig.instance3 -Database $global:dbName -Confirm:$false -ErrorAction SilentlyContinue
        }
        It "Should transfer all tables" {
            $result = Invoke-DbaDbTransfer -SqlInstance $global:testConfig.instance2 -DestinationSqlInstance $global:testConfig.instance3 -Database $global:dbName -CopyAll Tables
            $tables = Get-DbaDbTable -SqlInstance $global:testConfig.instance3 -Database $global:dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $global:db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test").id
            $global:db.Query("select id from dbo.transfer_test4").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $global:testConfig.instance2
            $result.SourceDatabase | Should -Be $global:dbName
            $result.DestinationInstance | Should -Be $global:testConfig.instance3
            $result.DestinationDatabase | Should -Be $global:dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be "Success"
            $result.Log -join "`n" | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
        }
        It "Should transfer select tables piping the transfer object" {
            $sourceTables = Get-DbaDbTable -SqlInstance $global:testConfig.instance2 -Database $global:dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $global:testConfig.instance2 -DestinationSqlInstance $global:testConfig.instance3 -Database $global:dbName
            $result = $transfer | Invoke-DbaDbTransfer
            $tables = Get-DbaDbTable -SqlInstance $global:testConfig.instance3 -Database $global:dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $global:db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $global:db.Query("select id from dbo.transfer_test").id | Should -BeIn $global:db2.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $global:testConfig.instance2
            $result.SourceDatabase | Should -Be $global:dbName
            $result.DestinationInstance | Should -Be $global:testConfig.instance3
            $result.DestinationDatabase | Should -Be $global:dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be "Success"
            $result.Log -join "`n" | Should -BeLike "*CREATE TABLE `[dbo`].`[transfer_test`]*"
        }
    }
}
