#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaAgentJob",
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
                "Job",
                "ExcludeJob",
                "InputObject",
                "Wait",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command execution and functionality" {
        It -Skip "Should stop an agent job and return CurrentRunStatus of Idle" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Start-DbaAgentJob | Stop-DbaAgentJob
            $results.CurrentRunStatus | Should -Be 'Idle'
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Start a job so we have something to stop
            $job = Get-DbaAgentJob -SqlInstance $TestConfig.instance1 -EnableException | Select-Object -First 1
            if ($job) {
                $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance1 -Job $job.Name
                $result = Stop-DbaAgentJob -SqlInstance $TestConfig.instance1 -Job $job.Name -Wait -EnableException
            }
        }

        It "Returns the documented output type" {
            if ($result) {
                $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
            } else {
                Set-ItResult -Skipped -Because "No running job available to test"
            }
        }

        It "Has the expected SMO Job properties" {
            if ($result) {
                $expectedProps = @(
                    'Name',
                    'Enabled',
                    'CurrentRunStatus',
                    'LastRunOutcome',
                    'LastRunDate',
                    'NextRunDate',
                    'OwnerLoginName'
                )
                $actualProps = $result.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in SMO Job object"
                }
            } else {
                Set-ItResult -Skipped -Because "No running job available to test"
            }
        }

        It "Returns job with Idle status when -Wait is used" {
            if ($result) {
                $result.CurrentRunStatus | Should -Be 'Idle' -Because "-Wait should ensure job stops before returning"
            } else {
                Set-ItResult -Skipped -Because "No running job available to test"
            }
        }
    }
}