#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Write-DbaDbTableData",
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
                "Database",
                "InputObject",
                "Table",
                "Schema",
                "BatchSize",
                "NotifyAfter",
                "AutoCreateTable",
                "NoTableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Truncate",
                "BulkCopyTimeOut",
                "ColumnMap",
                "EnableException",
                "UseDynamicStringLength"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $random = Get-Random
        $dbName = "dbatoolsci_writedbadaatable$random"
        $server.Query("CREATE DATABASE $dbName")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $server -Database $dbName | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # calling random function to throw data into a table
    It "defaults to dbo if no schema is specified" {
        Get-ChildItem | Select-Object -First 5 Name, Length, LastWriteTime | Write-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database $dbName -Table "childitem" -AutoCreateTable

        # Refresh tables to ensure we see the newly created objects
        $server.Databases[$dbName].Tables.Refresh()

        ($server.Databases[$dbName].Tables | Where-Object { $PSItem.Schema -eq "dbo" -and $PSItem.Name -eq "childitem" }).Count | Should -Be 1
    }

    It "automatically creates schema when using AutoCreateTable" {
        $schemaName = "testschema$random"
        $tableName = "testtable$random"

        $splatWrite = @{
            SqlInstance     = $TestConfig.instance1
            Database        = $dbName
            Schema          = $schemaName
            Table           = $tableName
            AutoCreateTable = $true
        }
        Get-ChildItem | Select-Object -First 5 Name, Length, LastWriteTime | Write-DbaDbTableData @splatWrite

        # Refresh schemas and tables to ensure we see the newly created objects
        $server.Databases[$dbName].Schemas.Refresh()
        $server.Databases[$dbName].Tables.Refresh()

        # Verify schema was created
        $server.Databases[$dbName].Schemas.Name | Should -Contain $schemaName

        # Verify table was created in the correct schema
        ($server.Databases[$dbName].Tables | Where-Object { $PSItem.Schema -eq $schemaName -and $PSItem.Name -eq $tableName }).Count | Should -Be 1
    }

    It "skips schema creation for temp tables" {
        $tableName = "##globaltemptest$random"

        $splatWrite = @{
            SqlInstance     = $TestConfig.instance1
            Database        = "tempdb"
            Table           = $tableName
            AutoCreateTable = $true
        }
        Get-ChildItem | Select-Object -First 5 Name, Length, LastWriteTime | Write-DbaDbTableData @splatWrite

        # Verify table was created in tempdb.dbo (not in any custom schema)
        $tempDbServer = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $tempDbServer.Databases["tempdb"].Tables.Refresh()

        ($tempDbServer.Databases["tempdb"].Tables | Where-Object { $PSItem.Schema -eq "dbo" -and $PSItem.Name -eq $tableName }).Count | Should -Be 1
    }
}