#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbDataClassification",
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
                "InformationType",
                "InformationTypeId",
                "SensitivityLabel",
                "SensitivityLabelId",
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
        $dbName = "dbatoolsci_setdataclass_$random"
        $tableName = "dbatoolsci_table_$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

        # Create a test table with columns
        $db.Query("CREATE TABLE dbo.$tableName (Id INT, Email NVARCHAR(255), SSN NVARCHAR(20))")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "sets a classification with known information type and sensitivity label" {
            $splatSet = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                Table            = $tableName
                Column           = "Email"
                InformationType  = "Contact Info"
                SensitivityLabel = "Confidential"
                Confirm          = $false
            }
            $result = Set-DbaDbDataClassification @splatSet
            $result | Should -Not -BeNullOrEmpty
            $result.InformationType | Should -Be "Contact Info"
            $result.SensitivityLabel | Should -Be "Confidential"
            $result.InformationTypeId | Should -Be "5C503E21-22C6-81FA-620B-F369B8EC38D1"
            $result.SensitivityLabelId | Should -Be "331F0B13-76B5-2F1B-A77B-DEF5A73C73C2"
        }

        It "updates an existing classification" {
            $splatUpdate = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                Table            = $tableName
                Column           = "Email"
                SensitivityLabel = "Highly Confidential"
                Confirm          = $false
            }
            $result = Set-DbaDbDataClassification @splatUpdate
            $result.SensitivityLabel | Should -Be "Highly Confidential"
            $result.SensitivityLabelId | Should -Be "B82CE05B-60A9-4CF3-8A8A-D6A0BB76E903"
        }

        It "supports piping from Get-DbaDbDataClassification" {
            $splatGet = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Column      = "Email"
            }
            $result = Get-DbaDbDataClassification @splatGet | Set-DbaDbDataClassification -SensitivityLabel "General" -Confirm:$false
            $result.SensitivityLabel | Should -Be "General"
        }

        It "sets classification with custom information type and explicit GUID" {
            $splatCustom = @{
                SqlInstance        = $TestConfig.InstanceSingle
                Database           = $dbName
                Table              = $tableName
                Column             = "SSN"
                InformationType    = "SSN"
                InformationTypeId  = "D936EC2C-04A4-9CF7-44C2-378A96456C61"
                SensitivityLabel   = "Highly Confidential - GDPR"
                Confirm            = $false
            }
            $result = Set-DbaDbDataClassification @splatCustom
            $result.InformationType | Should -Be "SSN"
            $result.InformationTypeId | Should -Be "D936EC2C-04A4-9CF7-44C2-378A96456C61"
            $result.SensitivityLabel | Should -Be "Highly Confidential - GDPR"
        }
    }
}
