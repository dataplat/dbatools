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
    Context "Command finds objects by name in a user database" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $dbName = "dbatoolsci_findobject"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbName

            $createObjects = @"
CREATE TABLE dbo.ServiceTable (ServiceId INT, ServiceName VARCHAR(100));
CREATE TABLE dbo.CustomerTable (CustomerId INT, CustomerName VARCHAR(100));
CREATE VIEW dbo.ServiceView AS SELECT * FROM dbo.ServiceTable;
CREATE PROCEDURE dbo.GetServiceData AS SELECT * FROM dbo.ServiceTable;
CREATE FUNCTION dbo.GetServiceCount() RETURNS INT AS BEGIN RETURN (SELECT COUNT(*) FROM dbo.ServiceTable); END;
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbName -Query $createObjects
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false
        }

        It "Should find objects with 'Service' in their name" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Pattern     = "Service"
            }
            $results = Find-DbaObject @splatFind
            $results.Count | Should -BeGreaterOrEqual 4
            $results.ObjectName | Should -Contain "ServiceTable"
            $results.ObjectName | Should -Contain "ServiceView"
            $results.ObjectName | Should -Contain "GetServiceData"
            $results.ObjectName | Should -Contain "GetServiceCount"
        }

        It "Should find only tables when ObjectType is specified" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Pattern     = "Table"
                ObjectType  = "Table"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.ObjectType | Should -All -Be "Table"
            $results.ObjectName | Should -Contain "ServiceTable"
            $results.ObjectName | Should -Contain "CustomerTable"
        }

        It "Should find columns with 'Service' when IncludeColumns is specified" {
            $splatFind = @{
                SqlInstance    = $TestConfig.instance2
                Database       = $dbName
                Pattern        = "Service"
                IncludeColumns = $true
            }
            $results = Find-DbaObject @splatFind
            $columnResults = $results | Where-Object MatchType -eq "ColumnName"
            $columnResults | Should -Not -BeNullOrEmpty
            $columnResults.ColumnName | Should -Contain "ServiceId"
            $columnResults.ColumnName | Should -Contain "ServiceName"
        }

        It "Should exclude databases when ExcludeDatabase is specified" {
            $splatFind = @{
                SqlInstance     = $TestConfig.instance2
                Pattern         = "Service"
                ExcludeDatabase = $dbName
            }
            $results = Find-DbaObject @splatFind
            $results.Database | Should -Not -Contain $dbName
        }

        It "Should find only views when ObjectType is View" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Pattern     = "Service"
                ObjectType  = "View"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.ObjectType | Should -All -Be "View"
            $results.ObjectName | Should -Contain "ServiceView"
        }

        It "Should find stored procedures when ObjectType is StoredProcedure" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Pattern     = "Service"
                ObjectType  = "StoredProcedure"
            }
            $results = Find-DbaObject @splatFind
            $results | Should -Not -BeNullOrEmpty
            $results.ObjectType | Should -All -Be "StoredProcedure"
            $results.ObjectName | Should -Contain "GetServiceData"
        }
    }

    Context "Command handles regex patterns correctly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $dbName = "dbatoolsci_findobjectregex"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbName

            $createObjects = @"
CREATE TABLE dbo.UserAccount (Id INT);
CREATE TABLE dbo.UserProfile (Id INT);
CREATE TABLE dbo.CustomerAccount (Id INT);
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $dbName -Query $createObjects
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false
        }

        It "Should find objects starting with 'User' using regex" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbName
                Pattern     = "^User"
            }
            $results = Find-DbaObject @splatFind
            $results.Count | Should -Be 2
            $results.ObjectName | Should -Contain "UserAccount"
            $results.ObjectName | Should -Contain "UserProfile"
            $results.ObjectName | Should -Not -Contain "CustomerAccount"
        }
    }
}
