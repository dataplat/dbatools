#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileGroup",
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
                "InputObject",
                "FileGroup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $multifgdb = "dbatoolsci_multifgdb$random"

        # Remove any existing database before creating
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $multifgdb

        # Create the test database with multiple filegroups
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("CREATE DATABASE $multifgdb; ALTER DATABASE $multifgdb ADD FILEGROUP [Test1]; ALTER DATABASE $multifgdb ADD FILEGROUP [Test2];")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $multifgdb -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Returns values for Instance" {
        BeforeAll {
            $results = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns the correct object" {
            $results[0].GetType().ToString() | Should -Be "Microsoft.SqlServer.Management.Smo.FileGroup"
        }
    }

    Context "Accepts database and filegroup input" {
        BeforeAll {
            $allFileGroupResults = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $multifgdb
            $singleFileGroupResult = Get-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $multifgdb -FileGroup Test1
        }

        It "Reports the right number of filegroups for database" {
            $allFileGroupResults.Count | Should -BeExactly 3
        }

        It "Reports the right number of filegroups for specific filegroup" {
            $singleFileGroupResult.Count | Should -BeExactly 1
        }
    }

    Context "Accepts piped input" {
        BeforeAll {
            $pipedResults = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeUser | Get-DbaDbFileGroup
        }

        It "Reports the right number of filegroups" {
            $pipedResults.Count | Should -BeExactly 4
        }

        It "Excludes User Databases" {
            $pipedResults.Parent.Name | Should -Not -Contain $multifgdb
            $pipedResults.Parent.Name | Should -Contain "msdb"
        }
    }
}