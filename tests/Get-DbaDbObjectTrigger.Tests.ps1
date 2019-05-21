$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbObjectTrigger).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_addtriggertoobject"
        $tablename = "dbo.dbatoolsci_trigger"
        $triggertablename = "dbatoolsci_triggerontable"
        $triggertable = @"
CREATE TRIGGER $triggertablename
    ON $tablename
    AFTER INSERT
    AS
    BEGIN
        SELECT 'Trigger on $tablename table'
    END
"@

        $viewname = "dbo.dbatoolsci_view"
        $triggerviewname = "dbatoolsci_triggeronview"
        $triggerview = @"
CREATE TRIGGER $triggerviewname
    ON $viewname
    INSTEAD OF INSERT
    AS
    BEGIN
        SELECT 'TRIGGER on $viewname view'
    END
"@
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("create database $dbname")

        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname
        $db.Query("CREATE TABLE $tablename (id int);")
        $db.Query("$triggertable")

        $db.Query("CREATE VIEW $viewname AS SELECT * FROM $tablename;")
        $db.Query("$triggerview")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("DROP DATABASE dbatoolsci_addtriggertoobject")
    }

    Context "Gets Table Trigger" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 | Where-Object {$_.name -eq "dbatoolsci_triggerontable"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should BeLike '*dbatoolsci_trigger table*'
        }
    }
    Context "Gets Table Trigger when using -Database" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database "dbatoolsci_addtriggertoobject" | Where-Object {$_.name -eq "dbatoolsci_triggerontable"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should BeLike '*dbatoolsci_trigger table*'
        }
    }
    Context "Gets View Trigger" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 | Where-Object {$_.name -eq "dbatoolsci_triggeronview"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should BeLike '*dbatoolsci_view view*'
        }
    }
    Context "Gets View Trigger when using -Database" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database "dbatoolsci_addtriggertoobject" | Where-Object {$_.name -eq "dbatoolsci_triggeronview"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should BeLike '*dbatoolsci_view view*'
        }
    }
}