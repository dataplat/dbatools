#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLastBackup",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $dbname = "dbatoolsci_getlastbackup$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("ALTER DATABASE $dbname SET RECOVERY FULL WITH NO_WAIT")
        $backupdir = Join-Path $TestConfig.Temp $dbname
        if (-not (Test-Path $backupdir -PathType Container)) {
            $null = New-Item -Path $backupdir -ItemType Container
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase
        Remove-Item -Path $backupdir -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get null history for database" {
        It "doesn't have any values for last backups because none exist yet" {
            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            $results.LastFullBackup | Should -BeNullOrEmpty
            $results.LastDiffBackup | Should -BeNullOrEmpty
            $results.LastLogBackup | Should -BeNullOrEmpty
        }
    }

    Context "Get last history for single database" {
        It "returns a date within the proper range" {
            $yesterday = (Get-Date).AddDays(-1)
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Differential
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupdir -Type Log
            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            [datetime]$results.LastFullBackup -gt $yesterday | Should -Be $true
            [datetime]$results.LastDiffBackup -gt $yesterday | Should -Be $true
            [datetime]$results.LastLogBackup -gt $yesterday | Should -Be $true
        }
    }

    Context "Get last history for all databases" {
        It "returns more than 3 databases" {
            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle
            $results.Status.Count -gt 3 | Should -Be $true
            $results.Database -contains $dbname | Should -Be $true
        }
    }

    Context "Get last history for one split database" {
        It "supports multi-file backups" {
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -BackupDirectory $backupdir -FileCount 4
            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Select-Object -First 1
            $results.LastFullBackup.GetType().Name | Should -Be "DbaDateTime"
        }
    }

    Context "Filter backups" {
        It "by 'is_copy_only'" {
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -BackupDirectory $backupdir -Type Full -CopyOnly
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -BackupDirectory $backupdir -Type Log -CopyOnly

            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle
            $copyOnlyFullBackup = $results | Where-Object Database -eq $dbname | Where-Object LastFullBackupIsCopyOnly -eq $true
            $copyOnlyLogBackup = $results | Where-Object Database -eq $dbname | Where-Object LastLogBackupIsCopyOnly -eq $true

            $copyOnlyFullBackup.Database | Should -Be $dbname
            $copyOnlyLogBackup.Database | Should -Be $dbname


            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -BackupDirectory $backupdir -Type Full
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -BackupDirectory $backupdir -Type Log

            $results = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbname

            $results.LastFullBackupIsCopyOnly | Should -Be $false
            $results.LastLogBackupIsCopyOnly | Should -Be $false
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected additional properties" {
            $additionalProps = @(
                "RecoveryModel",
                "SinceFull",
                "SinceDiff",
                "SinceLog",
                "LastFullBackupIsCopyOnly",
                "LastDiffBackupIsCopyOnly",
                "LastLogBackupIsCopyOnly",
                "DatabaseCreated",
                "DaysSinceDbCreated",
                "Status"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available via Select-Object *"
            }
        }

        It "LastFullBackup is DbaDateTime type" {
            $result.LastFullBackup | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        }

        It "LastDiffBackup is DbaDateTime type" {
            $result.LastDiffBackup | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        }

        It "LastLogBackup is DbaDateTime type" {
            $result.LastLogBackup | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        }
    }
}