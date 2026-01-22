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

    Context "Output Validation" {
        BeforeAll {
            $tempFile = [System.IO.Path]::GetTempFileName()
            "test content" | Out-File -FilePath $tempFile -Force
            
            $splatConnection = @{
                SqlInstance     = $TestConfig.instance1
                Database        = "tempdb"
                EnableException = $true
            }
            
            $tableName = "dbatools_import_test_$(Get-Random)"
            $createTableSql = "CREATE TABLE $tableName (id INT IDENTITY(1,1) PRIMARY KEY, FileName NVARCHAR(255), FileData VARBINARY(MAX))"
            Invoke-DbaQuery @splatConnection -Query $createTableSql
            
            $splatImport = @{
                SqlInstance     = $TestConfig.instance1
                Database        = "tempdb"
                Table           = $tableName
                FilePath        = $tempFile
                EnableException = $true
            }
            $result = Import-DbaBinaryFile @splatImport
        }
        
        AfterAll {
            if ($tempFile -and (Test-Path $tempFile)) {
                Remove-Item $tempFile -Force
            }
            if ($tableName) {
                $dropTableSql = "IF OBJECT_ID('$tableName', 'U') IS NOT NULL DROP TABLE $tableName"
                Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database "tempdb" -Query $dropTableSql
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "FilePath",
                "Status"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns Status property with Success value" {
            $result.Status | Should -Be "Success"
        }
    }
}
