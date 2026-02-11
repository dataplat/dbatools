#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaBinaryFileTable",
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
                "EnableException",
                "InputObject"
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
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test binary file tables, we need a table with binary data

        # Set variables. They are available in all the It blocks.
        $tableName = "BunchOFilez"
        $database = "tempdb"

        # Create the objects.
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database
        $null = $db.Query("CREATE TABLE [dbo].[$tableName]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")

        $splatImport = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $database
            Table       = $tableName
            FilePath    = "$($TestConfig.appveyorlabrepo)\azure\adalsql.msi"
        }
        $null = Import-DbaBinaryFile @splatImport

        $null = Get-ChildItem "$($TestConfig.appveyorlabrepo)\certificates" | Import-DbaBinaryFile -SqlInstance $TestConfig.InstanceSingle -Database $database -Table $tableName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("DROP TABLE dbo.BunchOFilez")

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns a table" {
        $results = Get-DbaBinaryFileTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $results.Name.Count | Should -BeGreaterOrEqual 1
    }

    It "supports piping" {
        $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb | Get-DbaBinaryFileTable
        $results.Name.Count | Should -BeGreaterOrEqual 1
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaBinaryFileTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Table"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "Name",
                "BinaryColumn",
                "FileNameColumn"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}