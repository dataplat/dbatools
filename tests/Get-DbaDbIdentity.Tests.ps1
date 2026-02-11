#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbIdentity",
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
                "Table",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (Id int NOT NULL IDENTITY (125, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example(Value) Select 1;
        CREATE TABLE dbo.dbatoolsci_example2 (Id int NOT NULL IDENTITY (5, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example2(Value) Select 1;")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example;
        DROP TABLE dbo.dbatoolsci_example2")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "Cmd",
                "IdentityValue",
                "ColumnValue",
                "Output"
            )
            $result = Get-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example2"
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }

        It "Returns results for each table" {
            $result.Count | Should -BeExactly 2
        }

        It "Returns correct results" {
            $result[0].IdentityValue | Should -BeExactly 125
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table "dbo.dbatoolsci_example"
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "Cmd",
                "IdentityValue",
                "ColumnValue",
                "Output"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the output object"
            }
        }
    }
}