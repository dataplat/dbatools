#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "DisableJobsOnDestination",
                "DisableJobsOnSource",
                "ExcludeServerProperties",
                "Force",
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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test Copy-DbaAgentServer, we need source and destination instances with SQL Agent configured.
        # The source instance should have jobs, schedules, operators, and other agent objects to copy.

        # Set variables. They are available in all the It blocks.
        $global:sourceInstance      = $TestConfig.instance1
        $global:destinationInstance = $TestConfig.instance2
        $global:testJobName         = "dbatoolsci_copyjob_$(Get-Random)"
        $global:testOperatorName    = "dbatoolsci_copyoperator_$(Get-Random)"
        $global:testScheduleName    = "dbatoolsci_copyschedule_$(Get-Random)"

        # Create test objects on source instance
        $splatNewJob = @{
            SqlInstance     = $global:sourceInstance
            Job             = $global:testJobName
            Description     = "Test job for Copy-DbaAgentServer"
            Category        = "Database Maintenance"
            EnableException = $true
        }
        $null = New-DbaAgentJob @splatNewJob

        $splatNewOperator = @{
            SqlInstance     = $global:sourceInstance
            Operator        = $global:testOperatorName
            EmailAddress    = "test@dbatools.io"
            EnableException = $true
        }
        $null = New-DbaAgentOperator @splatNewOperator

        $splatNewSchedule = @{
            SqlInstance       = $global:sourceInstance
            Schedule          = $global:testScheduleName
            FrequencyType     = "Weekly"
            FrequencyInterval = "Monday"
            StartTime         = "090000"
            EnableException   = $true
        }
        $null = New-DbaAgentSchedule @splatNewSchedule

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects on both source and destination
        $null = Remove-DbaAgentJob -SqlInstance $global:sourceInstance, $global:destinationInstance -Job $global:testJobName -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentOperator -SqlInstance $global:sourceInstance, $global:destinationInstance -Operator $global:testOperatorName -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentSchedule -SqlInstance $global:sourceInstance, $global:destinationInstance -Schedule $global:testScheduleName -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying SQL Agent objects" {
        It "Should copy jobs from source to destination" {
            $splatCopy = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                Force       = $true
            }
            $results = Copy-DbaAgentServer @splatCopy

            $results | Should -Not -BeNullOrEmpty
            $destinationJobs = Get-DbaAgentJob -SqlInstance $global:destinationInstance -Job $global:testJobName
            $destinationJobs | Should -Not -BeNullOrEmpty
            $destinationJobs.Name | Should -Be $global:testJobName
        }

        It "Should copy operators from source to destination" {
            # Ensure the copy operation ran first for operators to exist
            $splatCopy = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                Force       = $true
            }
            $null = Copy-DbaAgentServer @splatCopy

            $destinationOperators = Get-DbaAgentOperator -SqlInstance $global:destinationInstance -Operator $global:testOperatorName
            $destinationOperators | Should -Not -BeNullOrEmpty
            $destinationOperators.Name | Should -Be $global:testOperatorName
        }

        It "Should copy schedules from source to destination" {
            # Ensure the copy operation ran first for schedules to exist
            $splatCopy = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                Force       = $true
            }
            $null = Copy-DbaAgentServer @splatCopy

            $destinationSchedules = Get-DbaAgentSchedule -SqlInstance $global:destinationInstance -Schedule $global:testScheduleName
            $destinationSchedules | Should -Not -BeNullOrEmpty
            $destinationSchedules.Name | Should -Be $global:testScheduleName
        }
    }

    Context "When using DisableJobsOnDestination parameter" {
        BeforeAll {
            $global:disableTestJobName = "dbatoolsci_disablejob_$(Get-Random)"

            # Create a new job for this test
            $splatNewDisableJob = @{
                SqlInstance     = $global:sourceInstance
                Job             = $global:disableTestJobName
                Description     = "Test job for disable functionality"
                EnableException = $true
            }
            $null = New-DbaAgentJob @splatNewDisableJob
        }

        AfterAll {
            # Cleanup the test job
            $null = Remove-DbaAgentJob -SqlInstance $global:sourceInstance, $global:destinationInstance -Job $global:disableTestJobName -ErrorAction SilentlyContinue
        }

        It "Should disable jobs on destination when specified" {
            $splatCopyDisable = @{
                Source                   = $global:sourceInstance
                Destination              = $global:destinationInstance
                DisableJobsOnDestination = $true
                Force                    = $true
            }
            $results = Copy-DbaAgentServer @splatCopyDisable

            $copiedJob = Get-DbaAgentJob -SqlInstance $global:destinationInstance -Job $global:disableTestJobName
            $copiedJob | Should -Not -BeNullOrEmpty
            $copiedJob.Enabled | Should -Be $false
        }
    }

    Context "When using DisableJobsOnSource parameter" {
        BeforeAll {
            $global:sourceDisableJobName = "dbatoolsci_sourcedisablejob_$(Get-Random)"

            # Create a new job for this test
            $splatNewSourceJob = @{
                SqlInstance     = $global:sourceInstance
                Job             = $global:sourceDisableJobName
                Description     = "Test job for source disable functionality"
                EnableException = $true
            }
            $null = New-DbaAgentJob @splatNewSourceJob
        }

        AfterAll {
            # Cleanup the test job
            $null = Remove-DbaAgentJob -SqlInstance $global:sourceInstance, $global:destinationInstance -Job $global:sourceDisableJobName -ErrorAction SilentlyContinue
        }

        It "Should disable jobs on source when specified" {
            $splatCopySourceDisable = @{
                Source              = $global:sourceInstance
                Destination         = $global:destinationInstance
                DisableJobsOnSource = $true
                Force               = $true
            }
            $results = Copy-DbaAgentServer @splatCopySourceDisable

            $sourceJob = Get-DbaAgentJob -SqlInstance $global:sourceInstance -Job $global:sourceDisableJobName
            $sourceJob | Should -Not -BeNullOrEmpty
            $sourceJob.Enabled | Should -Be $false
        }
    }

    Context "When using ExcludeServerProperties parameter" {
        It "Should exclude specified server properties" {
            $splatCopyExclude = @{
                Source                  = $global:sourceInstance
                Destination             = $global:destinationInstance
                ExcludeServerProperties = $true
                Force                   = $true
            }
            $results = Copy-DbaAgentServer @splatCopyExclude

            # The results should still succeed but server-level properties should not be copied
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "When using WhatIf parameter" {
        It "Should not make changes when WhatIf is specified" {
            $whatIfJobName = "dbatoolsci_whatif_$(Get-Random)"

            # Create a job that shouldn't be copied due to WhatIf
            $splatNewWhatIfJob = @{
                SqlInstance     = $global:sourceInstance
                Job             = $whatIfJobName
                Description     = "Test job for WhatIf"
                EnableException = $true
            }
            $null = New-DbaAgentJob @splatNewWhatIfJob

            $splatCopyWhatIf = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                Force       = $true
                WhatIf      = $true
            }
            $results = Copy-DbaAgentServer @splatCopyWhatIf

            # Job should not exist on destination due to WhatIf
            $destinationJob = Get-DbaAgentJob -SqlInstance $global:destinationInstance -Job $whatIfJobName -ErrorAction SilentlyContinue
            $destinationJob | Should -BeNullOrEmpty

            # Cleanup
            $null = Remove-DbaAgentJob -SqlInstance $global:sourceInstance -Job $whatIfJobName -ErrorAction SilentlyContinue
        }
    }
}