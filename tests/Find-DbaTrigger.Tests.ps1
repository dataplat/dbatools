#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Pattern",
                "TriggerLevel",
                "IncludeSystemObjects",
                "IncludeSystemDatabases",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds Triggers at the Server Level" {
        BeforeAll {
            ## All Triggers adapted from examples on:
            ## https://docs.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-2017

            $ServerTrigger = @"
CREATE TRIGGER dbatoolsci_ddl_trig_database
ON ALL SERVER
FOR CREATE_DATABASE
AS
    PRINT 'dbatoolsci Database Created.'
    SELECT EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]','nvarchar(max)')
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $ServerTrigger
        }

        AfterAll {
            $DropTrigger = @"
DROP TRIGGER dbatoolsci_ddl_trig_database
ON ALL SERVER;
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database "Master" -Query $DropTrigger
        }

        It "Should find a specific Trigger at the Server Level" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -IncludeSystemDatabases -IncludeSystemObjects -TriggerLevel Server
            $results.TriggerLevel | Should -Be "Server"
            $results.DatabaseId | Should -BeNullOrEmpty
        }

        It "Should find a specific Trigger named dbatoolsci_ddl_trig_database" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -IncludeSystemDatabases -IncludeSystemObjects -TriggerLevel Server
            $results.Name | Should -Be "dbatoolsci_ddl_trig_database"
        }

        It "Should find a specific Trigger when TriggerLevel is All" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -TriggerLevel All
            $results.Name | Should -Be "dbatoolsci_ddl_trig_database"
        }
    }

    Context "Command finds Triggers at the Database and Object Level" {
        BeforeAll {
            ## All Triggers adapted from examples on:
            ## https://docs.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-2017

            $dbatoolsci_triggerdb = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_triggerdb"
            $DatabaseTrigger = @"
CREATE TRIGGER dbatoolsci_safety
ON DATABASE
FOR DROP_SYNONYM
AS
IF (@@ROWCOUNT = 0)
RETURN;
   RAISERROR ('You must disable Trigger "safety" to drop synonyms!',10, 1)
   ROLLBACK
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_triggerdb" -Query $DatabaseTrigger
            $TableTrigger = @"
CREATE TABLE dbo.Customer (id int, PRIMARY KEY (id));
GO
CREATE TRIGGER dbatoolsci_reminder1
ON dbo.Customer
AFTER INSERT, UPDATE
AS RAISERROR ('Notify Customer Relations', 16, 10);
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_triggerdb" -Query $TableTrigger
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_triggerdb" -Confirm:$false
        }

        It "Should find a specific Trigger at the Database Level" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -Database "dbatoolsci_triggerdb" -TriggerLevel Database
            $results.TriggerLevel | Should -Be "Database"
            $results.DatabaseId | Should -Be $dbatoolsci_triggerdb.ID
        }

        It "Should find a specific Trigger named dbatoolsci_safety" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -Database "dbatoolsci_triggerdb" -TriggerLevel Database
            $results.Name | Should -Be "dbatoolsci_safety"
        }

        It "Should find a specific Trigger at the Object Level" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -Database "dbatoolsci_triggerdb" -ExcludeDatabase Master -TriggerLevel Object
            $results.TriggerLevel | Should -Be "Object"
            $results.DatabaseId | Should -Be $dbatoolsci_triggerdb.ID
        }

        It "Should find a specific Trigger named dbatoolsci_reminder1" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -Database "dbatoolsci_triggerdb" -ExcludeDatabase Master -TriggerLevel Object
            $results.Name | Should -Be "dbatoolsci_reminder1"
        }

        It "Should find a specific Trigger on the Table [dbo].[Customer]" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -Database "dbatoolsci_triggerdb" -ExcludeDatabase Master -TriggerLevel Object
            $results.Object | Should -Be "[dbo].[Customer]"
        }

        It "Should find 2 Triggers when TriggerLevel is All" {
            $results = Find-DbaTrigger -SqlInstance $TestConfig.instance2 -Pattern dbatoolsci* -TriggerLevel All
            $results.name | Should -Be @("dbatoolsci_safety", "dbatoolsci_reminder1")
            $results.DatabaseId | Should -Be $dbatoolsci_triggerdb.ID, $dbatoolsci_triggerdb.ID
        }
    }
}