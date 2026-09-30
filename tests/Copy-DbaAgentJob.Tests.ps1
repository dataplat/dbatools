#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Job",
                "ExcludeJob",
                "DisableOnSource",
                "DisableOnDestination",
                "Force",
                "NewName",
                "UseLastModified",
                "InputObject",
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
        # To test copying agent jobs, we need to create test jobs on the source instance that can be copied to the destination

        # Set variables. They are available in all the It blocks.
        $sourceJobName = "dbatoolsci_copyjob"
        $sourceJobDisabledName = "dbatoolsci_copyjob_disabled"

        # Create the objects.
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $sourceJobName
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $sourceJobDisabledName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command copies jobs properly" {
        BeforeAll {
            $results = Copy-DbaAgentJob -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob
        }

        It "returns one success" {
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob_disabled | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            $splatCopyJob = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Job                  = "dbatoolsci_copyjob_disabled"
                DisableOnSource      = $true
                DisableOnDestination = $true
                Force                = $true
            }
            $results = Copy-DbaAgentJob @splatCopyJob

            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
        }
    }

    Context "Regression test for issue #9982" {
        It "copies all jobs when -Job parameter is not specified" {
            # Copy all jobs without specifying -Job parameter, using -Force to ensure they copy even if they exist
            $results = Copy-DbaAgentJob -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Force

            # Both jobs should be copied
            $results.Name | Should -Contain "dbatoolsci_copyjob"
            $results.Name | Should -Contain "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Not -Contain "Skipped"
            $results.Status | Should -Not -Contain "Failed"

            # Verify jobs exist on destination
            $destJobsCopied = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled
            $destJobsCopied.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "UseLastModified parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $testJobModified = "dbatoolsci_copyjob_modified"
            $testScheduleName = "dbatoolsci_copyjob_schedule"

            # Source job with a schedule, so schedule-only changes can be exercised
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobModified
            $splatSchedule = @{
                SqlInstance       = $TestConfig.InstanceCopy1
                Job               = $testJobModified
                Schedule          = $testScheduleName
                FrequencyType     = "Daily"
                FrequencyInterval = "EveryDay"
                StartDate         = (Get-Date).ToString("yyyyMMdd")
                StartTime         = "080000"
                Force             = $true
            }
            $null = New-DbaAgentSchedule @splatSchedule
            Start-Sleep -Seconds 2

            # Initial copy: destination now carries a later date_modified than the source
            $splatInitialCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Job         = $testJobModified
            }
            $null = Copy-DbaAgentJob @splatInitialCopy

            # Read msdb directly so assertions don't depend on cached SMO objects
            $queryJobRow = "SELECT job_id, enabled, date_modified FROM dbo.sysjobs WHERE name = @jobName"
            $queryScheduleTime = "
SELECT s.active_start_time
FROM dbo.sysjobs AS j
INNER JOIN dbo.sysjobschedules AS js ON js.job_id = j.job_id
INNER JOIN dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
WHERE j.name = @jobName AND s.name = @scheduleName"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # Pipe from Get so a job that never got created (failed setup) doesn't turn cleanup into a second failure
            $null = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Job dbatoolsci_copyjob_modified | Remove-DbaAgentJob
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "skips job when definitions are identical even though date_modified differs" {
            $sourceRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database msdb -Query $queryJobRow -SqlParameter @{ jobName = $testJobModified }
            $destRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database msdb -Query $queryJobRow -SqlParameter @{ jobName = $testJobModified }
            $sourceRow.date_modified | Should -Not -Be $destRow.date_modified

            $splatUseModified = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Job             = $testJobModified
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Name | Should -Be $testJobModified
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -BeLike "*identical*"
        }

        It "updates job when source is newer" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobModified -Description "Modified description"
            Start-Sleep -Seconds 2
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Job             = $testJobModified
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Name | Should -Be $testJobModified
            $result.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job $testJobModified).Description | Should -Be "Modified description"
        }

        It "aligns enabled state in place without recreating the job" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $destJobIdBefore = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database msdb -Query $queryJobRow -SqlParameter @{ jobName = $testJobModified }).job_id
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobModified -Disabled
            Start-Sleep -Seconds 2
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Job             = $testJobModified
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Status | Should -Be "Successful"
            $result.Notes | Should -BeLike "*in place*"
            $destRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database msdb -Query $queryJobRow -SqlParameter @{ jobName = $testJobModified }
            $destRow.enabled | Should -Be 0
            $destRow.job_id | Should -Be $destJobIdBefore
        }

        It "recreates job when only the schedule changed on the source" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # sp_update_schedule touches sysschedules.date_modified only, never sysjobs.date_modified
            $splatUpdateSchedule = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Database     = "msdb"
                Query        = "EXEC dbo.sp_update_schedule @name = @scheduleName, @active_start_time = 100000"
                SqlParameter = @{ scheduleName = $testScheduleName }
            }
            $null = Invoke-DbaQuery @splatUpdateSchedule
            Start-Sleep -Seconds 2
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Job             = $testJobModified
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Status | Should -Be "Successful"
            $splatCheck = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Database     = "msdb"
                Query        = $queryScheduleTime
                SqlParameter = @{ jobName = $testJobModified; scheduleName = $testScheduleName }
            }
            (Invoke-DbaQuery @splatCheck).active_start_time | Should -Be 100000
        }

        It "does not churn a job kept disabled with -DisableOnDestination" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobModified -Enabled
            $splatForceDisabled = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Job                  = $testJobModified
                Force                = $true
                DisableOnDestination = $true
            }
            $null = Copy-DbaAgentJob @splatForceDisabled
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Job                  = $testJobModified
                UseLastModified      = $true
                DisableOnDestination = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -BeLike "*identical*"
        }

        It "applies -DisableOnSource when the job is identical on the destination" {
            $splatUseModified = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Job                  = $testJobModified
                UseLastModified      = $true
                DisableOnDestination = $true
                DisableOnSource      = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -BeLike "*identical*"
            $sourceRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database msdb -Query $queryJobRow -SqlParameter @{ jobName = $testJobModified }
            $sourceRow.enabled | Should -Be 0
        }

        It "skips job when definition differs but destination is newer" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # Guarantee the destination edit lands after the source's last change
            Start-Sleep -Seconds 2
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job $testJobModified -Description "Changed on destination"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Job             = $testJobModified
                UseLastModified = $true
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -BeLike "*destination job is newer than source*"
            ($warn -join " ") | Should -Match "newer on destination"
        }
    }

    Context "Regression test for issue #9316 - alert-to-job links preserved with -Force" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $testJobWithAlert = "dbatoolsci_copyjob_alert"
            $testAlertName = "dbatoolsci_alert_for_job"

            # Create job on both instances
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobWithAlert
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job $testJobWithAlert

            # Create alert on destination that references the job
            $splatCreateAlert = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "msdb"
                Query       = @"
EXEC msdb.dbo.sp_add_alert
    @name = N'$testAlertName',
    @message_id = 0,
    @severity = 16,
    @enabled = 1,
    @delay_between_responses = 0,
    @include_event_description_in = 1,
    @job_name = N'$testJobWithAlert'
"@
            }
            $null = Invoke-DbaQuery @splatCreateAlert

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatDropAlert = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "msdb"
                Query       = "EXEC msdb.dbo.sp_delete_alert @name = N'$testAlertName'"
            }
            $null = Invoke-DbaQuery @splatDropAlert -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $testJobWithAlert -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job $testJobWithAlert -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "preserves alert-to-job link when copying with -Force" {
            # Copy the job with -Force, which should drop and recreate it
            $splatCopyForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Job         = $testJobWithAlert
                Force       = $true
            }
            $result = Copy-DbaAgentJob @splatCopyForce

            $result.Status | Should -Be "Successful"

            # Verify the alert still has the job association
            $splatCheckAlert = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "msdb"
                Query       = @"
SELECT a.name as AlertName, j.name as JobName
FROM msdb.dbo.sysalerts a
LEFT JOIN msdb.dbo.sysjobs j ON a.job_id = j.job_id
WHERE a.name = '$testAlertName'
"@
            }
            $alertCheck = Invoke-DbaQuery @splatCheckAlert

            $alertCheck.AlertName | Should -Be $testAlertName
            $alertCheck.JobName | Should -Be $testJobWithAlert
        }
    }

    Context "-NewName parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $sourceNewNameJob = "dbatoolsci_newname_source"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $sourceNewNameJob
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job "dbatoolsci_newname_source", "dbatoolsci_newname_copy" -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job "dbatoolsci_newname_renamed" -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "copies job to same server with new name" {
            $splatSameServer = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy1
                Job         = $sourceNewNameJob
                NewName     = "dbatoolsci_newname_copy"
            }
            $result = Copy-DbaAgentJob @splatSameServer

            $result.Name | Should -Be "dbatoolsci_newname_copy"
            $result.Status | Should -Be "Successful"
            $copiedJob = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job "dbatoolsci_newname_copy"
            $copiedJob | Should -Not -BeNullOrEmpty
        }

        It "fails when copying to same server without -NewName" {
            $splatNoNewName = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy1
                Job             = $sourceNewNameJob
                EnableException = $true
            }
            { Copy-DbaAgentJob @splatNoNewName } | Should -Throw
        }

        It "copies job to different server with new name" {
            $splatDiffServer = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Job         = $sourceNewNameJob
                NewName     = "dbatoolsci_newname_renamed"
            }
            $result = Copy-DbaAgentJob @splatDiffServer

            $result.Name | Should -Be "dbatoolsci_newname_renamed"
            $result.Status | Should -Be "Successful"
            $renamedJob = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job "dbatoolsci_newname_renamed"
            $renamedJob | Should -Not -BeNullOrEmpty
        }
    }
}
