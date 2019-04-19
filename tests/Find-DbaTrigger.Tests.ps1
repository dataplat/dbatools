$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Pattern', 'TriggerLevel', 'IncludeSystemObjects', 'IncludeSystemDatabases', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Pattern', 'TriggerLevel', 'IncludeSystemObjects', 'IncludeSystemDatabases', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
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
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $ServerTrigger
        }
        AfterAll {
            $DropTrigger = @"
DROP TRIGGER dbatoolsci_ddl_trig_database
ON ALL SERVER;
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $DropTrigger
        }

        $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -IncludeSystemDatabases -IncludeSystemObjects -TriggerLevel Server
        It "Should find a specific Trigger at the Server Level" {
            $results.TriggerLevel | Should Be "Server"
        }
        It "Should find a specific Trigger named dbatoolsci_ddl_trig_database" {
            $results.Name | Should Be "dbatoolsci_ddl_trig_database"
        }
        $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -TriggerLevel All
        It "Should find a specific Trigger when TriggerLevel is All" {
            $results.Name | Should Be "dbatoolsci_ddl_trig_database"
        }
    }
    Context "Command finds Triggers at the Database and Object Level" {
        BeforeAll {
            ## All Triggers adapted from examples on:
            ## https://docs.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-2017

            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_triggerdb'
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

        $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -TriggerLevel Database
        It "Should find a specific Trigger at the Database Level" {
            $results.TriggerLevel | Should Be "Database"
        }
        It "Should find a specific Trigger named dbatoolsci_safety" {
            $results.Name | Should Be "dbatoolsci_safety"
        }

        $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -Database 'dbatoolsci_triggerdb' -ExcludeDatabase Master -TriggerLevel Object
        It "Should find a specific Trigger at the Object Level" {
            $results.TriggerLevel | Should Be "Object"
        }
        It "Should find a specific Trigger named dbatoolsci_reminder1" {
            $results.Name | Should Be "dbatoolsci_reminder1"
        }
        It "Should find a specific Trigger on the Table [dbo].[Customer]" {
            $results.Object | Should Be "[dbo].[Customer]"
        }
        $results = Find-DbaTrigger -SqlInstance $script:instance2 -Pattern dbatoolsci* -TriggerLevel All
        It "Should find 2 Triggers when TriggerLevel is All" {
            $results.name | Should Be @('dbatoolsci_safety', 'dbatoolsci_reminder1')
        }
    }
}