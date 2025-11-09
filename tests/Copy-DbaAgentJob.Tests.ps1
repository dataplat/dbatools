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
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $sourceJobName
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $sourceJobDisabledName
        $sourcejobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance2
        $destjobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance3

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $command = Get-Command $CommandName
            $hasParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
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
                "UseLastModified",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Command copies jobs properly" {
        BeforeAll {
            $results = Copy-DbaAgentJob -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Job dbatoolsci_copyjob
        }

        It "returns one success" {
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_disabled | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            $splatCopyJob = @{
                Source               = $TestConfig.instance2
                Destination          = $TestConfig.instance3
                Job                  = "dbatoolsci_copyjob_disabled"
                DisableOnSource      = $true
                DisableOnDestination = $true
                Force                = $true
            }
            $results = Copy-DbaAgentJob @splatCopyJob

            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_disabled).Enabled | Should -BeFalse
        }
    }

    Context "UseLastModified parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a test job on both source and destination with same modification date
            $testJobModified = "dbatoolsci_copyjob_modified"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $testJobModified
            Start-Sleep -Seconds 2

            # Copy to destination first time
            $splatInitialCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Job         = $testJobModified
            }
            $null = Copy-DbaAgentJob @splatInitialCopy

            # Ensure both jobs have the exact same date_modified by setting destination to match source
            $escapedJobName = $testJobModified.Replace("'", "''")
            $sourceDate = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database msdb -Query "SELECT date_modified FROM dbo.sysjobs WHERE name = '$escapedJobName'" | Select-Object -ExpandProperty date_modified
            $updateQuery = "UPDATE msdb.dbo.sysjobs SET date_modified = '$($sourceDate.ToString("yyyy-MM-dd HH:mm:ss.fff"))' WHERE name = '$escapedJobName'"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance3 -Query $updateQuery

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_copyjob_modified -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_copyjob_modified -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "skips job when dates are equal" {
            $splatUseModified = @{
                Source          = $TestConfig.instance2
                Destination     = $TestConfig.instance3
                Job             = "dbatoolsci_copyjob_modified"
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Name | Should -Be "dbatoolsci_copyjob_modified"
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -BeLike "*same modification date*"
        }

        It "updates job when source is newer" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Modify the source job to make it newer
            $sourceJob = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_copyjob_modified"
            $sourceJob.Description = "Modified description"
            $sourceJob.Alter()
            Start-Sleep -Seconds 2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatUseModified = @{
                Source          = $TestConfig.instance2
                Destination     = $TestConfig.instance3
                Job             = "dbatoolsci_copyjob_modified"
                UseLastModified = $true
            }
            $result = Copy-DbaAgentJob @splatUseModified

            $result.Name | Should -Be "dbatoolsci_copyjob_modified"
            $result.Status | Should -Be "Successful"
        }
    }
}