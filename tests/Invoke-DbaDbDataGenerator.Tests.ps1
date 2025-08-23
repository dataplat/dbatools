#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDataGenerator",
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
                "FilePath",
                "Locale",
                "CharacterString",
                "Table",
                "Column",
                "ExcludeTable",
                "ExcludeColumn",
                "MaxValue",
                "ExactLength",
                "ModulusFactor",
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
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test the data generator, we need a database with a test table.

        # Set variables. They are available in all the It blocks.
        $generatorDb = "dbatoolsci_generator"
        $createTableSql = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [varchar](100) NULL
                ) ON [PRIMARY];"

        # Create the objects.
        New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $generatorDb
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $generatorDb -Query $createTableSql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $generatorDb

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "Starts with the right data" {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $generatorDb -Query "select * from people" | Should -Be $null
        }

        It "Returns the proper output" {
            $configFile = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.instance2 -Database $generatorDb -Path $backupPath -Rows 10

            $results = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.instance2 -Database $generatorDb -FilePath $configFile.FullName

            foreach ($result in $results) {
                $result.Rows | Should -Be 10
                $result.Database | Should -Contain $generatorDb
            }

        }
        It "Generates the data" {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database $generatorDb -Query "select * from people" | Should -Not -Be $null
        }
    }
}