#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaBinaryFile",
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
                "Schema",
                "Statement",
                "FileNameColumn",
                "BinaryColumn",
                "NoFileNameColumn",
                "InputObject",
                "FilePath",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "tempdb"
        $tableName = "dbatoolsci_binaryfile_$(Get-Random)"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Query "CREATE TABLE $tableName (FileName VARCHAR(255), FileData VARBINARY(MAX))"

        $testFilePath = "$($TestConfig.Temp)\dbatoolsci_testfile_$(Get-Random).txt"
        [System.IO.File]::WriteAllText($testFilePath, "dbatools binary file test content")

        $result = Import-DbaBinaryFile -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Table $tableName -FilePath $testFilePath

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Query "DROP TABLE IF EXISTS $tableName" -ErrorAction SilentlyContinue
        Remove-Item $testFilePath -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "FilePath",
                "Status"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has correct Status value" {
            $result[0].Status | Should -Be "Success"
        }

        It "Has correct Database and Table values" {
            $result[0].Database | Should -Be $dbName
            $result[0].Table | Should -Be $tableName
        }
    }
}
