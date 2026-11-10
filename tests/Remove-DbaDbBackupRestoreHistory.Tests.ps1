#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbBackupRestoreHistory",
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
                "KeepDays",
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When the database was dropped" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Dropping a database leaves its backup history in msdb, see issue #10818
            $droppedDbName = "dbatoolsci_droppedhistory_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $droppedDbName
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName -Type Full -FilePath nul
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Has the backup history of the dropped database before the removal" {
            Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName | Should -Not -BeNullOrEmpty
        }

        It "Removes the backup history of the dropped database" {
            Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName
            $WarnVar | Should -BeNullOrEmpty
            Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $droppedDbName | Should -BeNullOrEmpty
        }
    }

    Context "When KeepDays is 0" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $keepDaysDbName = "dbatoolsci_keepdayszero_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $keepDaysDbName
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $keepDaysDbName -Type Full -FilePath nul
            # sp_delete_backuphistory removes what finished before the cutoff, and SMO passes the cutoff in whole seconds
            Start-Sleep -Seconds 2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $keepDaysDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Has the backup history of the database before the removal" {
            Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $keepDaysDbName | Should -Not -BeNullOrEmpty
        }

        It "Removes the backup history up to now instead of keeping 30 days" {
            Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.InstanceSingle -KeepDays 0
            $WarnVar | Should -BeNullOrEmpty
            Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $keepDaysDbName | Should -BeNullOrEmpty
        }
    }

    Context "When the clock of this computer is behind the instance" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $clockDbName = "dbatoolsci_clockbehind_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $clockDbName
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $clockDbName -Type Full -FilePath nul
            # sp_delete_backuphistory removes what finished before the cutoff, and SMO passes the cutoff in whole seconds
            Start-Sleep -Seconds 2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The computer of issue #10818 ran five hours behind its instance, a container in UTC. A test computer shares
            # the clock of its instance, so only the clock of this computer is moved back, the instance stays real.
            Mock -ModuleName dbatools -CommandName Get-Date -ParameterFilter { $PesterBoundParameters.Count -eq 0 } -MockWith { [datetime]::Now.AddHours(-5) }
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $clockDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Counts the days back from the clock of the instance" {
            Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.InstanceSingle -KeepDays 0
            $WarnVar | Should -BeNullOrEmpty
            Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $clockDbName | Should -BeNullOrEmpty
        }
    }

    Context "When KeepDays is used with Database" {
        It "Refuses the combination also for KeepDays 0" {
            Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.InstanceSingle -KeepDays 0 -Database "dbatoolsci_nosuchdb_$(Get-Random)" -WarningAction SilentlyContinue
            $WarnVar | Should -Match "KeepDays cannot be used with Database"
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>