#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaintenanceSolutionLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LogType",
                "Since",
                "Path",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create a temporary database for testing maintenance solution logs
        $testDatabaseName = "dbatoolsci_maintenance_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.Instance1 -Name $testDatabaseName

        # Create test log entries to simulate maintenance solution output
        $splatLogSetup = @{
            SqlInstance = $TestConfig.Instance1
            Database    = $testDatabaseName
            Query       = @"
                CREATE TABLE [dbo].[CommandLog] (
                    [ID] [int] IDENTITY(1,1) NOT NULL,
                    [DatabaseName] [sysname] NULL,
                    [SchemaName] [sysname] NULL,
                    [ObjectName] [sysname] NULL,
                    [ObjectType] [char](2) NULL,
                    [IndexName] [sysname] NULL,
                    [IndexType] [tinyint] NULL,
                    [StatisticsName] [sysname] NULL,
                    [PartitionNumber] [int] NULL,
                    [ExtendedInfo] [xml] NULL,
                    [Command] [nvarchar](max) NOT NULL,
                    [CommandType] [nvarchar](60) NOT NULL,
                    [StartTime] [datetime] NOT NULL,
                    [EndTime] [datetime] NULL,
                    [ErrorNumber] [int] NULL,
                    [ErrorMessage] [nvarchar](max) NULL
                );

                INSERT INTO [dbo].[CommandLog] (DatabaseName, Command, CommandType, StartTime, EndTime)
                VALUES
                    ('TestDB1', 'BACKUP DATABASE [TestDB1]', 'BACKUP_DATABASE', GETDATE()-1, GETDATE()-1),
                    ('TestDB2', 'DBCC CHECKDB([TestDB2])', 'DBCC_CHECKDB', GETDATE()-2, GETDATE()-2),
                    ('TestDB1', 'ALTER INDEX ALL ON [TestDB1].[dbo].[TestTable] REBUILD', 'ALTER_INDEX', GETDATE()-3, GETDATE()-3);
"@
        }
        $null = Invoke-DbaQuery @splatLogSetup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the test database
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.Instance1 -Database $testDatabaseName -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When retrieving maintenance solution logs" {
        It "Returns log entries when CommandLog table exists" {
            $splatCommand = @{
                SqlInstance = $TestConfig.Instance1
                Path        = $testDatabaseName
            }
            $results = Get-DbaMaintenanceSolutionLog @splatCommand
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
        }

        It "Filters by LogType parameter" {
            $splatBackupLogs = @{
                SqlInstance = $TestConfig.Instance1
                Path        = $testDatabaseName
                LogType     = "Backup"
            }
            $backupResults = Get-DbaMaintenanceSolutionLog @splatBackupLogs
            $backupResults | Should -Not -BeNullOrEmpty
            $backupResults | Where-Object CommandType -like "*BACKUP*" | Should -Not -BeNullOrEmpty
        }

        It "Filters by Since parameter" {
            $splatSinceLogs = @{
                SqlInstance = $TestConfig.Instance1
                Path        = $testDatabaseName
                Since       = (Get-Date).AddDays(-1)
            }
            $recentResults = Get-DbaMaintenanceSolutionLog @splatSinceLogs
            $recentResults | Should -Not -BeNullOrEmpty
        }

        It "Handles non-existent database gracefully" {
            $splatNonExistent = @{
                SqlInstance = $TestConfig.Instance1
                Path        = "NonExistentDatabase"
            }
            { Get-DbaMaintenanceSolutionLog @splatNonExistent -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "Works with SqlCredential parameter" -Skip:$($null -eq $TestConfig.SqlCredential) {
            $splatWithCred = @{
                SqlInstance   = $TestConfig.Instance1
                SqlCredential = $TestConfig.SqlCredential
                Path          = $testDatabaseName
            }
            $results = Get-DbaMaintenanceSolutionLog @splatWithCred
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatResults = @{
                SqlInstance = $TestConfig.Instance1
                Path        = $testDatabaseName
            }
            $testResults = Get-DbaMaintenanceSolutionLog @splatResults
        }

        It "Returns objects with expected properties" {
            $testResults | Should -Not -BeNullOrEmpty
            $testResults[0] | Should -HaveProperty "DatabaseName"
            $testResults[0] | Should -HaveProperty "Command"
            $testResults[0] | Should -HaveProperty "CommandType"
            $testResults[0] | Should -HaveProperty "StartTime"
        }

        It "Returns datetime objects for time fields" {
            $testResults[0].StartTime | Should -BeOfType [DateTime]
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>