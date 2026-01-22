#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJob",
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
                "Schedule",
                "ScheduleId",
                "NewName",
                "Enabled",
                "Disabled",
                "Description",
                "StartStepId",
                "Category",
                "OwnerLogin",
                "EventLogLevel",
                "EmailLevel",
                "NetsendLevel",
                "PageLevel",
                "EmailOperator",
                "NetsendOperator",
                "PageOperator",
                "DeleteLevel",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Context "Output Validation" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $jobName = "dbatoolsci_test_$(Get-Random)"
        $null = New-DbaAgentJob -SqlInstance $server -Job $jobName -Description "Test job for Set-DbaAgentJob"
        $result = Set-DbaAgentJob -SqlInstance $server -Job $jobName -Disabled -EnableException
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $server -Job $jobName -Confirm:$false
    }

    It "Returns the documented output type" {
        $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
    }

    It "Has the expected default display properties" {
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
        $actualProps = $result.PSObject.Properties.Name
        foreach ($prop in $expectedProps) {
            $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
        }
    }

    It "Returns modified job with updated properties" {
        $result.Name | Should -Be $jobName
        $result.Enabled | Should -Be $false
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>