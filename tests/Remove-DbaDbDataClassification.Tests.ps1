#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbDataClassification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
        $dbName = "dbatoolsci_removedataclass_$random"
        $tableName = "dbatoolsci_table_$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.SingleInstance -Name $dbName

        # Create a test table
        $db.Query("CREATE TABLE dbo.$tableName (Id INT, Email NVARCHAR(255), Phone NVARCHAR(20))")

        # Add classification to both columns
        foreach ($colName in "Email", "Phone") {
            $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_id', @value = N'5C503E21-22C6-81FA-620B-F369B8EC38D1', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'$colName'")
            $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_information_type_name', @value = N'Contact Info', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'$colName'")
            $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_sensitivity_label_id', @value = N'684A0DB2-D514-49D8-8C0C-DF84A7B083EB', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'$colName'")
            $db.Query("EXEC sys.sp_addextendedproperty @name = N'sys_sensitivity_label_name', @value = N'General', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'$tableName', @level2type = N'COLUMN', @level2name = N'$colName'")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.SingleInstance -Database $dbName -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "removes a classification from a column" {
            $classification = Get-DbaDbDataClassification -SqlInstance $TestConfig.SingleInstance -Database $dbName -Column "Email"
            $classification | Should -Not -BeNullOrEmpty

            $result = $classification | Remove-DbaDbDataClassification -Confirm:$false
            $result.Status | Should -Be "Removed"

            $afterRemove = Get-DbaDbDataClassification -SqlInstance $TestConfig.SingleInstance -Database $dbName -Column "Email"
            $afterRemove | Should -BeNullOrEmpty
        }

        It "removes all classifications when piping all results" {
            $before = Get-DbaDbDataClassification -SqlInstance $TestConfig.SingleInstance -Database $dbName
            $before | Should -Not -BeNullOrEmpty

            $before | Remove-DbaDbDataClassification -Confirm:$false

            $after = Get-DbaDbDataClassification -SqlInstance $TestConfig.SingleInstance -Database $dbName
            $after | Should -BeNullOrEmpty
        }
    }
}
