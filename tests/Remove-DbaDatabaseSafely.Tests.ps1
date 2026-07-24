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
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $db1
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $db2

        # The command checks its own preconditions against the DESTINATION instance: it probes
        # the SQL Agent service there over WMI and has that instance write the backup. So the
        # backup folder must be a share that both this runner and the instance service accounts
        # can write to, and the destination host must answer WMI.

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The scenarios drop the databases themselves, so only clean up what a partial run left behind.
        $leftoverDatabases = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $db1, $db2
        if ($leftoverDatabases) {
            $null = $leftoverDatabases | Remove-DbaDatabase
        }

        $restoreJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Job "Rationalised Database Restore Script for $db1", "Rationalised Database Restore Script for $db2"
        if ($restoreJobs) {
            $null = $restoreJobs | Remove-DbaAgentJob
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {
        It "Should restore to the same server" {
            $splatSameServer = @{
                SqlInstance   = $TestConfig.InstanceCopy1
                Database      = $db1
                BackupFolder  = $backupPath
                NoDbccCheckDb = $true
            }
            $results = Remove-DbaDatabaseSafely @splatSameServer
            $results.DatabaseName | Should -Be $db1
            $results.SqlInstance | Should -Be $TestConfig.InstanceCopy1
            $results.TestingInstance | Should -Be $TestConfig.InstanceCopy1
            $results.BackupFolder | Should -Be $backupPath

            # The whole point of the command: the database is gone once the restore verified.
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db1 | Should -BeNullOrEmpty
        }

        It "Should restore to another server" {
            $splatOtherServer = @{
                SqlInstance   = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $db2
                BackupFolder  = $backupPath
                NoDbccCheckDb = $true
            }
            $results = Remove-DbaDatabaseSafely @splatOtherServer
            $results.DatabaseName | Should -Be $db2
            $results.SqlInstance | Should -Be $TestConfig.InstanceCopy1
            $results.TestingInstance | Should -Be $TestConfig.InstanceCopy2
            $results.BackupFolder | Should -Be $backupPath

            # Dropped on the source, and the verification copy on the destination is cleaned up too.
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db2 | Should -BeNullOrEmpty
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $db2 | Should -BeNullOrEmpty
        }
    }
    Context "Confirmation suppression under -Force" {
        BeforeAll {
            # The suite pins '*-Dba*:Confirm' = $false, which latches the cmdlet runtime and masks
            # the behavior under test. Shadow the dictionary with a copy rather than mutating the
            # shared one.
            $suppressionDefaults = @{ }
            foreach ($entry in $TestConfig.Defaults.GetEnumerator()) {
                if ($entry.Key -notlike "*:Confirm") {
                    $suppressionDefaults[$entry.Key] = $entry.Value
                }
            }
            $PSDefaultParameterValues = $suppressionDefaults

            # The observation point: the SQL Agent probe is the first thing the process block does,
            # before any database is touched, and reporting a stopped agent ends the run right
            # there. It has to be a plain function and not a mock - a mock body does not see its
            # caller's scope, which is the whole thing being measured.
            #
            # `Get-Module dbatools` can return TWO modules - the base library's binary dbatools.dll
            # and this script module - and `& <two modules> { }` stringifies to a command named
            # "dbatools dbatools", so the script module has to be selected explicitly.
            $dbatoolsScriptModule = Get-Module -Name dbatools | Where-Object { $PSItem.Path -like "*.psm1" }
            & $dbatoolsScriptModule {
                function script:Get-DbaService {
                    [CmdletBinding()]
                    param(
                        [string]$ComputerName,
                        [string]$InstanceName,
                        [string]$Type,
                        [switch]$EnableException
                    )
                    $global:dbatoolsciSafelyProcessConfirmPreference = "$ConfirmPreference"
                    [PSCustomObject]@{ State = "Stopped"; Name = "SQLSERVERAGENT" }
                }
            }
        }

        AfterAll {
            # NOT function:script:Get-DbaService - the Function provider takes no scope qualifier,
            # so that path removes nothing and -ErrorAction SilentlyContinue hides the miss.
            $dbatoolsScriptModule = Get-Module -Name dbatools | Where-Object { $PSItem.Path -like "*.psm1" }
            & $dbatoolsScriptModule {
                Remove-Item -Path function:Get-DbaService -ErrorAction SilentlyContinue
            }
            Remove-Variable -Name dbatoolsciSafelyProcessConfirmPreference -Scope Global -ErrorAction SilentlyContinue
        }

        It "suppresses confirmation for the whole process block when -Force is used" {
            Mock -CommandName Test-DbaPath -ModuleName dbatools -MockWith { $true }
            $global:dbatoolsciSafelyProcessConfirmPreference = $null

            $splatForced = @{
                SqlInstance   = $TestConfig.InstanceCopy1
                Database      = "dbatoolsci_absent_$(Get-Random)"
                BackupFolder  = $backupPath
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabaseSafely @splatForced

            $global:dbatoolsciSafelyProcessConfirmPreference | Should -Be "none"
        }

        It "leaves the session preference alone without -Force" {
            Mock -CommandName Test-DbaPath -ModuleName dbatools -MockWith { $true }
            $global:dbatoolsciSafelyProcessConfirmPreference = $null

            $splatUnforced = @{
                SqlInstance   = $TestConfig.InstanceCopy1
                Database      = "dbatoolsci_absent_$(Get-Random)"
                BackupFolder  = $backupPath
                WarningAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabaseSafely @splatUnforced

            # Not-null FIRST: `Should -Not -Be "none"` passes vacuously on $null, i.e. it would pass
            # when the process block was never reached at all.
            $global:dbatoolsciSafelyProcessConfirmPreference | Should -Not -BeNullOrEmpty
            $global:dbatoolsciSafelyProcessConfirmPreference | Should -Not -Be "none"
        }
    }
}
