#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgBackupHistory",
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
                "AvailabilityGroup",
                "Database",
                "ExcludeDatabase",
                "IncludeCopyOnly",
                "Force",
                "Since",
                "RecoveryFork",
                "Last",
                "LastFull",
                "LastDiff",
                "LastLog",
                "DeviceType",
                "Raw",
                "LastLsn",
                "IncludeMirror",
                "Type",
                "LsnSort",
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
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # To get availability group backup history we need an availability group and a database with backups.
        # A single replica availability group with cluster type NONE is enough.
        $agName = "dbatoolsci_agbackuphistory"
        $agDbName = "dbatoolsci_agbhdb_$(Get-Random)"

        $splatAg = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatAg

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $agDbName
        $splatBackup = @{
            SqlInstance = $TestConfig.InstanceHadr
            Database    = $agDbName
            Path        = $backupPath
        }
        $null = Backup-DbaDatabase @splatBackup -Type Full -FilePath "agbh_full.bak"
        $splatAddAgDatabase = @{
            SqlInstance       = $TestConfig.InstanceHadr
            AvailabilityGroup = $agName
            Database          = $agDbName
        }
        $null = Add-DbaAgDatabase @splatAddAgDatabase
        $null = Backup-DbaDatabase @splatBackup -Type Log -FilePath "agbh_log.trn"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the last backup chain of the availability group" {
        BeforeAll {
            $results = @(Get-DbaAgBackupHistory -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -Last)
        }

        # Always include this test to be sure that the command runs without warnings.
        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns the full and the log backup tagged with the availability group name" {
            $results.Type | Should -Contain "Full"
            $results.Type | Should -Contain "Log"
            $results.AvailabilityGroupName | Select-Object -Unique | Should -Be $agName
        }
    }

    Context "Honors EnableException when no full backup anchors the chain #10621" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A history window that starts after the full backup and holds only a log backup, so the
            # last-chain selection finds a log backup but no full backup to anchor it. We use -Since
            # instead of deleting msdb history, because Backup-DbaDatabase refuses a log backup for a
            # database whose msdb history holds no full backup. The sleeps keep the timestamp strictly
            # between the existing backups and the new log backup.
            Start-Sleep -Seconds 1
            $sinceTime = Get-Date
            Start-Sleep -Seconds 1
            $null = Backup-DbaDatabase @splatBackup -Type Log -FilePath "agbh_log2.trn"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Throws with EnableException" {
            $splatAgHistory = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Last              = $true
                Since             = $sinceTime
                EnableException   = $true
            }
            { Get-DbaAgBackupHistory @splatAgHistory } | Should -Throw "*Fullname property not found*"
        }

        It "Still warns and returns nothing without EnableException" {
            $splatAgHistory = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Last              = $true
                Since             = $sinceTime
                WarningAction     = "SilentlyContinue"
            }
            $results = Get-DbaAgBackupHistory @splatAgHistory
            $WarnVar | Should -BeLike "*Fullname property not found*"
            $results | Should -BeNullOrEmpty
        }
    }
}