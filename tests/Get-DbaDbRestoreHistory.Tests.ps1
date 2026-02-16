#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbRestoreHistory",
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
                "ExcludeDatabase",
                "Since",
                "RestoreType",
                "Force",
                "Last",
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

        $random = Get-Random
        $dbname1 = "dbatoolsci_restorehistory1_$random"
        $dbname2 = "dbatoolsci_restorehistory2_$random"

        $sourceBak = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        $remoteBak = "$backupPath\singlerestore.bak"
        Copy-Item -Path $sourceBak -Destination $remoteBak

        $splatRestore1 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = $remoteBak
            DatabaseName          = $dbname1
            DestinationFilePrefix = $dbname1
        }
        $null = Restore-DbaDatabase @splatRestore1

        $splatRestore2 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = $remoteBak
            DatabaseName          = $dbname2
            DestinationFilePrefix = $dbname2
        }
        $null = Restore-DbaDatabase @splatRestore2

        $splatRestore3 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = $remoteBak
            DatabaseName          = $dbname2
            DestinationFilePrefix = "rsh_pre_$dbname2"
            WithReplace           = $true
        }
        $null = Restore-DbaDatabase @splatRestore3

        $fullBackup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Type Full -Path $backupPath
        $diffBackup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Type Diff -Path $backupPath
        $logBackup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Type Log -Path $backupPath

        $splatRestoreFinal = @{
            SqlInstance  = $TestConfig.InstanceSingle
            Path         = $diffBackup.BackupPath, $logBackup.BackupPath
            DatabaseName = $dbname1
            WithReplace  = $true
        }
        $null = Restore-DbaDatabase @splatRestoreFinal

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2 | Remove-DbaDatabase

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get last restore history for single database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname2 -Last -OutVariable "global:dbatoolsciOutput")
        }

        It "Results holds 1 object" {
            $results.Count | Should -Be 1
        }

        It "Should return the full restore with the correct properties" {
            $results[0].RestoreType | Should -Be "Database"
            $results[0].From | Should -BeLike "*singlerestore.bak"
            $results[0].To | Should -Match "\\rsh_pre_$dbname2"
        }
    }

    Context "Get last restore history for multiple database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2 -Last)
        }

        It "Results holds 2 objects" {
            $results.Count | Should -Be 2
        }

        It "Should return the full restore with the correct properties" {
            $results.RestoreType | Should -Contain "Database"
            $results.RestoreType | Should -Contain "Log"
            $results.From | Where-Object { $PSItem -like "*singlerestore.bak" } | Should -Not -BeNullOrEmpty
            $results.From | Should -Contain $logBackup.BackupPath
            ($results | Where-Object Database -eq $dbname1).To | Should -Match "\\$dbname1"
            ($results | Where-Object Database -eq $dbname2).To | Should -Match "\\rsh_pre_$dbname2"
        }
    }

    Context "Get complete restore history for multiple database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2)
        }

        It "Results holds correct number of objects" {
            $results.Count | Should -Be 6
        }

        It "Should return the full restore with the correct properties" {
            @($results | Where-Object Database -eq $dbname1).Count | Should -Be 4
            @($results | Where-Object Database -eq $dbname2).Count | Should -Be 2
        }
    }

    Context "return object properties" {
        It "has the correct properties" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2
            $result = $results[0]
            $ExpectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Username",
                "RestoreType",
                "Date",
                "From",
                "To",
                "first_lsn",
                "last_lsn",
                "checkpoint_lsn",
                "database_backup_lsn",
                "backup_finish_date",
                "BackupFinishDate",
                "RowError",
                "RowState",
                "Table",
                "ItemArray",
                "HasErrors"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)

            $ExpectedPropsDefault = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Username",
                "RestoreType",
                "Date",
                "From",
                "To",
                "BackupFinishDate"
            )
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }

    Context "Get restore history by restore type" {
        It "returns the correct history records for full db restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2 -RestoreType Database
            $results.Count | Should -Be 4
            @($results | Where-Object RestoreType -eq Database).Count | Should -Be 4
        }

        It "returns the correct history records for diffential restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -RestoreType Differential
            $results.Database | Should -Be $dbname1
            $results.RestoreType | Should -Be Differential
        }

        It "returns the correct history records for log restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -RestoreType Log
            $results.Database | Should -Be $dbname1
            $results.RestoreType | Should -Be Log
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Username",
                "RestoreType",
                "Date",
                "From",
                "To",
                "first_lsn",
                "last_lsn",
                "checkpoint_lsn",
                "database_backup_lsn",
                "backup_finish_date",
                "BackupFinishDate",
                "RowError",
                "RowState",
                "Table",
                "ItemArray",
                "HasErrors"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Username",
                "RestoreType",
                "Date",
                "From",
                "To",
                "BackupFinishDate"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}