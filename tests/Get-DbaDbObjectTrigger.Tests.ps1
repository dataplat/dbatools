#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbObjectTrigger",
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
                "Type",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("create database $dbname")

        $server.Query("CREATE TABLE $tablename (id int);", $dbname)
        $server.Query("$triggertable", $dbname)

        $server.Query("CREATE VIEW $viewname AS SELECT * FROM $tablename;", $dbname)
        $server.Query("$triggerview", $dbname)

        $systemDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Table Trigger" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $systemDbs.Name | Where-Object Name -eq "dbatoolsci_triggerontable"
        }
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
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Where-Object Name -eq "dbatoolsci_triggerontable"
        }
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
        BeforeAll {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table "dbatoolsci_trigger" | Get-DbaDbObjectTrigger
        }
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
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $systemDbs.Name | Where-Object Name -eq "dbatoolsci_triggeronview"
        }
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
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Where-Object Name -eq "dbatoolsci_triggeronview"
        }
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
        BeforeAll {
            $results = Get-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ExcludeSystemView | Get-DbaDbObjectTrigger
        }
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
        BeforeAll {
            $tableResults = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table "dbatoolsci_trigger"
            $viewResults = Get-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ExcludeSystemView
            $results = $tableResults, $viewResults | Get-DbaDbObjectTrigger
        }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should return two triggers" {
            $results.Count | Should -Be 2
        }
    }
    Context "Gets All types Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Type All
        }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should return two triggers" {
            $results.Count | Should -Be 2
        }
    }
    Context "Gets only Table Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Type Table
        }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be only one" {
            $results.Count | Should -Be 1
        }
        It "Should be a Table trigger" {
            $results.Parent.GetType().Name | Should -Be "Table"
        }
    }
    Context "Gets only View Trigger when using -Type" {
        BeforeAll {
            $results = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Type View
        }
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        It "Should be only one" {
            $results.Count | Should -Be 1
        }
        It "Should be a View trigger" {
            $results.Parent.GetType().Name | Should -Be "View"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbObjectTrigger -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Trigger]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Parent',
                'IsEnabled',
                'DateLastModified'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}