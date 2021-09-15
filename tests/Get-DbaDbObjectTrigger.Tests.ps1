$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbObjectTrigger).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Type', 'InputObject', 'EnableException'
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

        $server.Query("CREATE TABLE $tablename (id int);", $dbname)
        $server.Query("$triggertable", $dbname)

        $server.Query("CREATE VIEW $viewname AS SELECT * FROM $tablename;", $dbname)
        $server.Query("$triggerview", $dbname)

        $systemDbs = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeUser
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Gets Table Trigger" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -ExcludeDatabase $systemDbs.Name | Where-Object { $_.name -eq "dbatoolsci_triggerontable" }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }
    Context "Gets Table Trigger when using -Database" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database $dbname | Where-Object { $_.name -eq "dbatoolsci_triggerontable" }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }
    Context "Gets Table Trigger passing table object using pipeline" {
        $results = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbname -Table "dbatoolsci_trigger" | Get-DbaDbObjectTrigger
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }
    Context "Gets View Trigger" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -ExcludeDatabase $systemDbs.Name | Where-Object { $_.name -eq "dbatoolsci_triggeronview" }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }
    Context "Gets View Trigger when using -Database" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database $dbname | Where-Object { $_.name -eq "dbatoolsci_triggeronview" }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }
    Context "Gets View Trigger passing table object using pipeline" {
        $results = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname -ExcludeSystemView | Get-DbaDbObjectTrigger
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.isenabled | Should -Be $true
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }
    Context "Gets Table and View Trigger passing both objects using pipeline" {
        $tableResults = Get-DbaDbTable -SqlInstance $script:instance2 -Database $dbname -Table "dbatoolsci_trigger"
        $viewResults = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname -ExcludeSystemView
        $results = $tableResults, $viewResults | Get-DbaDbObjectTrigger
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be enabled" {
            $results.Count | Should -Be 2
        }
    }
    Context "Gets All types Trigger when using -Type" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database $dbname -Type All
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be only one" {
            $results.Count | Should -Be 2
        }
    }
    Context "Gets only Table Trigger when using -Type" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database $dbname -Type Table
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be only one" {
            $results.Count | Should -Be 1
        }
        It "Should have text of Trigger" {
            $results.Parent.GetType().Name | Should -Be "Table"
        }
    }
    Context "Gets only View Trigger when using -Type" {
        $results = Get-DbaDbObjectTrigger -SqlInstance $script:instance2 -Database $dbname -Type View
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be only one" {
            $results.Count | Should -Be 1
        }
        It "Should have text of Trigger" {
            $results.Parent.GetType().Name | Should -Be "View"
        }
    }
}