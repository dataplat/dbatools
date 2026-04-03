#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDataClassification",
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
                "Schema",
                "Table",
                "Column",
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

        $random = Get-Random
        $dbName = "dbatoolsci_dataclass_$random"
        $tableName = "dbatoolsci_table_$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbName

        # Create a test table with columns to classify
        $db.Query("CREATE TABLE dbo.$tableName (Id INT, EmailAddress NVARCHAR(255), CreditCardNumber NVARCHAR(20))")

        # Add classification extended properties to EmailAddress column
        $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_id', @value = N'5C503E21-22C6-81FA-620B-F369B8EC38D1', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'EmailAddress'")
        $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Contact Info', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'EmailAddress'")
        $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_sensitivity_label_id', @value = N'331F0B13-76B5-2F1B-A77B-DEF5A73C73C2', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'EmailAddress'")
        $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_sensitivity_label_name', @value = N'Confidential', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'EmailAddress'")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "finds classifications in a database" {
            $result = Get-DbaDbDataClassification -SqlInstance $TestConfig.instance2 -Database $dbName
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
        }

        It "returns correct classification details" {
            $result = Get-DbaDbDataClassification -SqlInstance $TestConfig.instance2 -Database $dbName
            $result.Table | Should -Be $tableName
            $result.Column | Should -Be "EmailAddress"
            $result.InformationType | Should -Be "Contact Info"
            $result.SensitivityLabel | Should -Be "Confidential"
        }

        It "filters by table" {
            $result = Get-DbaDbDataClassification -SqlInstance $TestConfig.instance2 -Database $dbName -Table $tableName
            $result | Should -Not -BeNullOrEmpty
        }

        It "filters by column" {
            $result = Get-DbaDbDataClassification -SqlInstance $TestConfig.instance2 -Database $dbName -Column "EmailAddress"
            $result | Should -Not -BeNullOrEmpty
            $result.Column | Should -Be "EmailAddress"
        }

        It "returns nothing for unclassified column filter" {
            $result = Get-DbaDbDataClassification -SqlInstance $TestConfig.instance2 -Database $dbName -Column "CreditCardNumber"
            $result | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $result = $db | Get-DbaDbDataClassification
            $result | Should -Not -BeNullOrEmpty
            $result.InformationType | Should -Be "Contact Info"
        }
    }
}
