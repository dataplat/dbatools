#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDatabaseSafely",
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
                "Destination",
                "DestinationSqlCredential",
                "NoDbccCheckDb",
                "BackupFolder",
                "CategoryName",
                "JobOwner",
                "AllDatabases",
                "BackupCompression",
                "ReuseSourceFolderStructure",
                "Force",
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

        $db1 = "dbatoolsci_safely"
        $db2 = "dbatoolsci_safely_otherInstance"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "Rationalised Database Restore Script for $db1"
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job "Rationalised Database Restore Script for $db2"

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {
        It "Should restore to the same server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.instance2 -Database $db1 -BackupFolder $backupPath -NoDbccCheckDb
            $results.DatabaseName | Should -Be $db1
            $results.SqlInstance | Should -Be $TestConfig.instance2
            $results.TestingInstance | Should -Be $TestConfig.instance2
            $results.BackupFolder | Should -Be $backupPath
        }

        It "Should restore to another server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.instance2 -Database $db2 -BackupFolder $backupPath -NoDbccCheckDb -Destination $TestConfig.instance3
            $results.DatabaseName | Should -Be $db2
            $results.SqlInstance | Should -Be $TestConfig.instance2
            $results.TestingInstance | Should -Be $TestConfig.instance3
            $results.BackupFolder | Should -Be $backupPath
        }
    }
}