#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbTransfer",
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
                "CopyAllObjects",
                "CopyAll",
                "SchemaOnly",
                "DataOnly",
                "ScriptingOption",
                "ScriptOnly",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbName = 'dbatools_transfer'
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
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
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName
    }
    Context "Testing scripting invocation" {
        It "Should script all objects" {
            $transfer = New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -CopyAllObjects
            $scripts = $transfer | Invoke-DbaDbTransfer -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
        It "Should script all tables with schema only" {
            $scripts = Invoke-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -CopyAll Tables -SchemaOnly -ScriptOnly
            $script = $scripts -join "`n"
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test2`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test3`]*'
            $script | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test4`]*'
        }
    }
    Context "Testing object transfer" {
        BeforeEach {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName
            $destination.Query("CREATE DATABASE $dbname")
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName
        }
        It "Should transfer all tables" {
            $result = Invoke-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -DestinationSqlInstance $TestConfig.InstanceMulti2 -Database $dbName -CopyAll Tables -OutVariable "global:dbatoolsciOutput"
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName -Table transfer_test, transfer_test2, transfer_test3, transfer_test4
            $tables.Count | Should -Be 4
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test4").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $db.Query("select id from dbo.transfer_test4").id | Should -BeIn $db2.Query("select id from dbo.transfer_test4").id
            $result.SourceInstance | Should -Be $TestConfig.InstanceMulti1
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.InstanceMulti2
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
        It "Should transfer select tables piping the transfer object" {
            $sourceTables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbName -Table transfer_test, transfer_test2
            $transfer = $sourceTables | New-DbaDbTransfer -SqlInstance $TestConfig.InstanceMulti1 -DestinationSqlInstance $TestConfig.InstanceMulti2 -Database $dbName
            $result = $transfer | Invoke-DbaDbTransfer
            $tables = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $dbName -Table transfer_test, transfer_test2
            $tables.Count | Should -Be 2
            $db.Query("select id from dbo.transfer_test").id | Should -Not -BeNullOrEmpty
            $db.Query("select id from dbo.transfer_test").id | Should -BeIn $db2.Query("select id from dbo.transfer_test").id
            $result.SourceInstance | Should -Be $TestConfig.InstanceMulti1
            $result.SourceDatabase | Should -Be $dbName
            $result.DestinationInstance | Should -Be $TestConfig.InstanceMulti2
            $result.DestinationDatabase | Should -Be $dbName
            $result.Elapsed.TotalMilliseconds | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Success'
            $result.Log -join "`n" | Should -BeLike '*CREATE TABLE `[dbo`].`[transfer_test`]*'
        }
    }
    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "SourceInstance",
                "SourceDatabase",
                "DestinationInstance",
                "DestinationDatabase",
                "Status",
                "Elapsed",
                "Log"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}