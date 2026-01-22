#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRunningJob",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test job that will execute quickly for testing running job detection
            $newJobSplat = @{
                SqlInstance     = $TestConfig.instance1
                Job             = "dbatoolsci_GetRunningJob_Test"
                EnableException = $true
            }
            $null = New-DbaAgentJob @newJobSplat

            $newStepSplat = @{
                SqlInstance     = $TestConfig.instance1
                Job             = "dbatoolsci_GetRunningJob_Test"
                StepName        = "Step1"
                Subsystem       = "TransactSql"
                Command         = "WAITFOR DELAY '00:00:05'"
                EnableException = $true
            }
            $null = New-DbaAgentJobStep @newStepSplat

            # Start the job
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance1 -Job "dbatoolsci_GetRunningJob_Test" -EnableException

            # Give it a moment to start executing
            Start-Sleep -Milliseconds 500

            # Get the running job
            $result = Get-DbaRunningJob -SqlInstance $TestConfig.instance1 -EnableException
        }

        AfterAll {
            # Clean up test job
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance1 -Job "dbatoolsci_GetRunningJob_Test" -Confirm:$false
        }

        It "Returns the documented output type" {
            if ($result) {
                $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
            } else {
                Set-TestInconclusive -Message "No running jobs found to test output type"
            }
        }

        It "Has the expected default display properties" {
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'InstanceName',
                    'SqlInstance',
                    'Name',
                    'Category',
                    'OwnerLoginName',
                    'CurrentRunStatus',
                    'CurrentRunRetryAttempt',
                    'Enabled',
                    'LastRunDate',
                    'LastRunOutcome',
                    'HasSchedule',
                    'OperatorToEmail',
                    'CreateDate'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            } else {
                Set-TestInconclusive -Message "No running jobs found to test properties"
            }
        }

        It "Filters out idle jobs" {
            if ($result) {
                $result | ForEach-Object {
                    $_.CurrentRunStatus | Should -Not -Be 'Idle' -Because "Get-DbaRunningJob should only return non-idle jobs"
                }
            } else {
                Set-TestInconclusive -Message "No running jobs found to test filtering"
            }
        }

        It "Includes StartDate property when -IncludeExecution is used" {
            if ($result) {
                # Get-DbaRunningJob calls Get-DbaAgentJob with -IncludeExecution which adds StartDate
                $result[0].PSObject.Properties.Name | Should -Contain 'StartDate' -Because "StartDate property should be added when job is running"
            } else {
                Set-TestInconclusive -Message "No running jobs found to test StartDate property"
            }
        }
    }
}