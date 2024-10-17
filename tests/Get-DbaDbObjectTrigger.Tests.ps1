param($ModuleName = 'dbatools')

Describe "Get-DbaDbObjectTrigger Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbObjectTrigger
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
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Get-DbaDbObjectTrigger Integration Tests" -Tag "IntegrationTests" {
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
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $server.Query("create database $dbname")

        $server.Query("CREATE TABLE $tablename (id int);", $dbname)
        $server.Query("$triggertable", $dbname)

        $server.Query("CREATE VIEW $viewname AS SELECT * FROM $tablename;", $dbname)
        $server.Query("$triggerview", $dbname)

        $systemDbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeUser
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Gets Table Trigger" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -ExcludeDatabase $systemDbs.Name | Where-Object { $_.name -eq "dbatoolsci_triggerontable" }
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }

    Context "Gets Table Trigger when using -Database" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -Database $dbname | Where-Object { $_.name -eq "dbatoolsci_triggerontable" }
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }

    Context "Gets Table Trigger passing table object using pipeline" {
        BeforeAll {
            $results = Get-DbaDbTable -SqlInstance $global:instance2 -Database $dbname -Table "dbatoolsci_trigger" | Get-DbaDbObjectTrigger
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_trigger table*'
        }
    }

    Context "Gets View Trigger" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -ExcludeDatabase $systemDbs.Name | Where-Object { $_.name -eq "dbatoolsci_triggeronview" }
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }

    Context "Gets View Trigger when using -Database" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -Database $dbname | Where-Object { $_.name -eq "dbatoolsci_triggeronview" }
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }

    Context "Gets View Trigger passing table object using pipeline" {
        BeforeAll {
            $results = Get-DbaDbView -SqlInstance $global:instance2 -Database $dbname -ExcludeSystemView | Get-DbaDbObjectTrigger
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be enabled" {
            $results.isenabled | Should -BeTrue
        }
        It "Should have text of Trigger" {
            $results.TextBody | Should -BeLike '*dbatoolsci_view view*'
        }
    }

    Context "Gets Table and View Trigger passing both objects using pipeline" {
        BeforeAll {
            $tableResults = Get-DbaDbTable -SqlInstance $global:instance2 -Database $dbname -Table "dbatoolsci_trigger"
            $viewResults = Get-DbaDbView -SqlInstance $global:instance2 -Database $dbname -ExcludeSystemView
            $results = $tableResults, $viewResults | Get-DbaDbObjectTrigger
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have two results" {
            $results.Count | Should -Be 2
        }
    }

    Context "Gets All types Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -Database $dbname -Type All
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have two results" {
            $results.Count | Should -Be 2
        }
    }

    Context "Gets only Table Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -Database $dbname -Type Table
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have only one result" {
            $results.Count | Should -Be 1
        }
        It "Should have a Table parent type" {
            $results.Parent.GetType().Name | Should -Be "Table"
        }
    }

    Context "Gets only View Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $global:instance2 -Database $dbname -Type View
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have only one result" {
            $results.Count | Should -Be 1
        }
        It "Should have a View parent type" {
            $results.Parent.GetType().Name | Should -Be "View"
        }
    }
}
