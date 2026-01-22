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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example2" -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Table',
                'Cmd',
                'IdentityValue',
                'ColumnValue',
                'Output'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns results for each table" {
            $result.Count | Should -BeExactly 2
        }

        It "Returns correct identity value" {
            $result[0].IdentityValue | Should -BeExactly 125
        }
    }
}