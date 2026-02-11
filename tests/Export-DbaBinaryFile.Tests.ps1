#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaBinaryFile",
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
                "FileNameColumn",
                "BinaryColumn",
                "Path",
                "Query",
                "FilePath",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $exportPath = "$($TestConfig.Temp)\exports-$CommandName-$(Get-Random)"
        $null = New-Item -Path $exportPath -ItemType Directory -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the export directory.
        Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When exporting binary files from database" {
        BeforeEach {
            # We want to run all commands in the BeforeEach block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Set up test table and data for each test
            $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $null = $db.Query("CREATE TABLE [dbo].[BunchOFilezz]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")

            $splatImportMain = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = "BunchOFilezz"
                FilePath    = "$($TestConfig.appveyorlabrepo)\azure\adalsql.msi"
            }
            $null = Import-DbaBinaryFile @splatImportMain

            $null = Get-ChildItem "$($TestConfig.appveyorlabrepo)\certificates" | Import-DbaBinaryFile -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table BunchOFilezz

            # We want to run all commands outside of the BeforeEach block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            # We want to run all commands in the AfterEach block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up test table
            $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $null = $db.Query("DROP TABLE dbo.BunchOFilezz")

            # Clean up exported files for this specific test
            Remove-Item -Path "$exportPath\*" -Recurse -ErrorAction SilentlyContinue

            # We want to run all commands outside of the AfterEach block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Exports the table data to file using SqlInstance" {
            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Path        = $exportPath
            }
            $results = Export-DbaBinaryFile @splatExport

            $results.Name.Count | Should -BeExactly 3
            $results.Name | Should -Be @("adalsql.msi", "localhost.crt", "localhost.pfx")
        }

        It "Exports the table data to file using pipeline from Get-DbaBinaryFileTable" {
            $results = Get-DbaBinaryFileTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb | Export-DbaBinaryFile -Path $exportPath

            $results.Name.Count | Should -BeExactly 3
            $results.Name | Should -Be @("adalsql.msi", "localhost.crt", "localhost.pfx")
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputExportPath = "$($TestConfig.Temp)\exports-$CommandName-output-$(Get-Random)"
            $null = New-Item -Path $outputExportPath -ItemType Directory -Force

            # Create a test table with binary data directly via SQL
            $outputDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $null = $outputDb.Query("CREATE TABLE [dbo].[dbatoolsci_BinaryOutput]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
            $null = $outputDb.Query("INSERT INTO [dbo].[dbatoolsci_BinaryOutput] ([FileName123], [TheFile123]) VALUES ('testfile.bin', CAST('test binary content' AS varbinary(max)))")

            $splatOutputExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = "dbatoolsci_BinaryOutput"
                Path        = $outputExportPath
            }
            $outputResult = Export-DbaBinaryFile @splatOutputExport

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $cleanDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $null = $cleanDb.Query("IF OBJECT_ID('dbo.dbatoolsci_BinaryOutput') IS NOT NULL DROP TABLE dbo.dbatoolsci_BinaryOutput")
            Remove-Item -Path $outputExportPath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $expectedProps = @("FullName", "Name", "DirectoryName", "Extension", "Length", "CreationTime", "LastWriteTime")
            foreach ($prop in $expectedProps) {
                $outputResult[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the FileInfo object"
            }
        }

        It "Has the correct filename" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].Name | Should -Be "testfile.bin"
        }
    }
}