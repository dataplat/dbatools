param($ModuleName = 'dbatools')

Describe "Find-DbaTrigger Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaTrigger
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String
        }
        It "Should have TriggerLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter TriggerLevel -Type String
        }
        It "Should have IncludeSystemObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObjects -Type Switch
        }
        It "Should have IncludeSystemDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Find-DbaTrigger Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command finds Triggers at the Server Level" {
        BeforeAll {
            $ServerTrigger = @"
CREATE TRIGGER dbatoolsci_ddl_trig_database
ON ALL SERVER
FOR CREATE_DATABASE
AS
    PRINT 'dbatoolsci Database Created.'
    SELECT EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]','nvarchar(max)')
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $ServerTrigger
        }
        AfterAll {
            $DropTrigger = @"
DROP TRIGGER dbatoolsci_ddl_trig_database
ON ALL SERVER;
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $DropTrigger
        }

        It "Should find a specific Trigger at the Server Level" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -IncludeSystemDatabases -IncludeSystemObjects -TriggerLevel Server
            $results.TriggerLevel | Should -Be "Server"
            $results.DatabaseId | Should -BeNullOrEmpty
        }
        It "Should find a specific Trigger named dbatoolsci_ddl_trig_database" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -IncludeSystemDatabases -IncludeSystemObjects -TriggerLevel Server
            $results.Name | Should -Be "dbatoolsci_ddl_trig_database"
        }
        It "Should find a specific Trigger when TriggerLevel is All" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -TriggerLevel All
            $results.Name | Should -Be "dbatoolsci_ddl_trig_database"
        }
    }

    Context "Command finds Triggers at the Database and Object Level" {
        BeforeAll {
            $dbatoolsci_triggerdb = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_triggerdb'
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
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'dbatoolsci_triggerdb' -Query $DatabaseTrigger
            $TableTrigger = @"
CREATE TABLE dbo.Customer (id int, PRIMARY KEY (id));
GO
CREATE TRIGGER dbatoolsci_reminder1
ON dbo.Customer
AFTER INSERT, UPDATE
AS RAISERROR ('Notify Customer Relations', 16, 10);
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'dbatoolsci_triggerdb' -Query $TableTrigger
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database 'dbatoolsci_triggerdb' -Confirm:$false
        }

        It "Should find a specific Trigger at the Database Level" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -TriggerLevel Database
            $results.TriggerLevel | Should -Be "Database"
            $results.DatabaseId | Should -Be $dbatoolsci_triggerdb.ID
        }
        It "Should find a specific Trigger named dbatoolsci_safety" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -TriggerLevel Database
            $results.Name | Should -Be "dbatoolsci_safety"
        }
        It "Should find a specific Trigger at the Object Level" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -ExcludeDatabase Master -TriggerLevel Object
            $results.TriggerLevel | Should -Be "Object"
            $results.DatabaseId | Should -Be $dbatoolsci_triggerdb.ID
        }
        It "Should find a specific Trigger named dbatoolsci_reminder1" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -ExcludeDatabase Master -TriggerLevel Object
            $results.Name | Should -Be "dbatoolsci_reminder1"
        }
        It "Should find a specific Trigger on the Table [dbo].[Customer]" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -ExcludeDatabase Master -TriggerLevel Object
            $results.Object | Should -Be "[dbo].[Customer]"
        }
        It "Should find 2 Triggers when TriggerLevel is All" {
            $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -TriggerLevel All
            $results.name | Should -Be @('dbatoolsci_safety', 'dbatoolsci_reminder1')
            $results.DatabaseId | Should -Be @($dbatoolsci_triggerdb.ID, $dbatoolsci_triggerdb.ID)
        }
    }
}
