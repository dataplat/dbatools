#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaObject",
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
                "ExcludeDatabase",
                "Pattern",
                "ObjectType",
                "IncludeColumns",
                "IncludeSystemObjects",
                "IncludeSystemDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testDbName = "dbatoolsci_findobject_$(Get-Random)"

        $splatNewDb = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $testDbName
        }
        $null = New-DbaDatabase @splatNewDb

        $createObjects = @"
CREATE TABLE dbo.ServiceOrder (
    ServiceOrderId INT IDENTITY PRIMARY KEY,
    ServiceName    NVARCHAR(100),
    CustomerCode   NVARCHAR(50)
);

CREATE TABLE dbo.CustomerAccount (
    CustomerAccountId INT IDENTITY PRIMARY KEY,
    AccountName       NVARCHAR(100),
    ServiceCode       NVARCHAR(50)
);
GO

CREATE VIEW dbo.v_ServiceSummary
AS
    SELECT ServiceOrderId, ServiceName
    FROM dbo.ServiceOrder;
GO

CREATE PROCEDURE dbo.usp_GetServiceOrders
AS
    SELECT * FROM dbo.ServiceOrder;
GO

CREATE TRIGGER trg_ServiceAudit
ON DATABASE
FOR CREATE_TABLE
AS
BEGIN
    SET NOCOUNT ON;
END;
GO
"@
        $splatCreateObjects = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $testDbName
            Query       = $createObjects
        }
        $null = Invoke-DbaQuery @splatCreateObjects

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveDb = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $testDbName
            Confirm     = $false
        }
        $null = Remove-DbaDatabase @splatRemoveDb

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Searching object names" {
        It "Should find tables whose names match the pattern" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "Service"
                ObjectType  = "Table"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "ServiceOrder"
        }

        It "Should find views whose names match the pattern" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "Service"
                ObjectType  = "View"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "v_ServiceSummary"
        }

        It "Should find stored procedures whose names match the pattern" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "ServiceOrders"
                ObjectType  = "StoredProcedure"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "usp_GetServiceOrders"
        }

        It "Should find database DDL triggers whose names match the pattern" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "ServiceAudit"
                ObjectType  = "Trigger"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "trg_ServiceAudit"
            $results.Schema | Should -BeNullOrEmpty
        }

        It "Should return MatchType of ObjectName for object name matches" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "ServiceOrder"
                ObjectType  = "Table"
            }
            $results = Find-DbaObject @splatFind
            $results.MatchType | Should -Be "ObjectName"
        }

        It "Should find objects across all types when ObjectType is All" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "Service"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            ($results | Where-Object ObjectType -eq "USER_TABLE") | Should -Not -BeNullOrEmpty
            ($results | Where-Object ObjectType -eq "VIEW") | Should -Not -BeNullOrEmpty
        }

        It "Should return no results when ExcludeDatabase is specified" {
            $splatFind = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Pattern         = "Service"
                ExcludeDatabase = $testDbName
            }
            $results = Find-DbaObject @splatFind
            $results | Where-Object Database -eq $testDbName | Should -BeNullOrEmpty
        }

        It "Should return results only for the specified database" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "Service"
            }
            $results = Find-DbaObject @splatFind
            $results.Database | Select-Object -Unique | Should -Be $testDbName
        }
    }

    Context "Searching column names" {
        It "Should find tables with columns matching the pattern when IncludeColumns is used" {
            $splatFind = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = $testDbName
                Pattern        = "ServiceName"
                IncludeColumns = $true
                ObjectType     = "Table"
            }
            $results = Find-DbaObject @splatFind
            $columnMatches = $results | Where-Object MatchType -eq "ColumnName"
            $columnMatches | Should -Not -BeNullOrEmpty
            $columnMatches.ColumnName | Should -Contain "ServiceName"
        }

        It "Should find columns with ServiceCode in CustomerAccount table" {
            $splatFind = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = $testDbName
                Pattern        = "Service"
                IncludeColumns = $true
                ObjectType     = "Table"
            }
            $results = Find-DbaObject @splatFind
            $columnMatches = $results | Where-Object MatchType -eq "ColumnName"
            $columnMatches | Should -Not -BeNullOrEmpty
            $columnMatches.ColumnName | Should -Contain "ServiceCode"
        }

        It "Should return MatchType of ColumnName for column matches" {
            $splatFind = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = $testDbName
                Pattern        = "ServiceName"
                IncludeColumns = $true
                ObjectType     = "Table"
            }
            $results = Find-DbaObject @splatFind
            $columnMatches = $results | Where-Object MatchType -eq "ColumnName"
            $columnMatches[0].MatchType | Should -Be "ColumnName"
        }

        It "Should not return column matches when IncludeColumns is not specified" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Pattern     = "ServiceName"
                ObjectType  = "Table"
            }
            $results = Find-DbaObject @splatFind
            $columnMatches = $results | Where-Object MatchType -eq "ColumnName"
            $columnMatches | Should -BeNullOrEmpty
        }
    }

    Context "System databases" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $systemDbTableName = "t_dbatoolsci_systemdb_$(Get-Random)"
            $splatCreateTable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
                Query       = "CREATE TABLE dbo.$systemDbTableName (Id INT IDENTITY PRIMARY KEY)"
            }
            $null = Invoke-DbaQuery @splatCreateTable

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatDropTable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
                Query       = "DROP TABLE dbo.$systemDbTableName"
            }
            $null = Invoke-DbaQuery @splatDropTable

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should include system databases when IncludeSystemDatabases is specified" {
            $splatFind = @{
                SqlInstance            = $TestConfig.InstanceSingle
                Pattern                = $systemDbTableName
                ObjectType             = "Table"
                IncludeSystemDatabases = $true
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Contain "master"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connection of the caller is left in the database it was in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_object_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -Query "CREATE TABLE dbo.dbatoolsci_table (id INT);"

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $contextResult = Find-DbaObject -SqlInstance $callerServer -Database $contextDbName -Pattern dbatoolsci

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still returns what it was asked for" {
            # Only a call that really runs can move the connection, so a command that returned nothing
            # would pass the assertion below for the wrong reason.
            $contextResult | Should -Not -BeNullOrEmpty
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }
    }
}
