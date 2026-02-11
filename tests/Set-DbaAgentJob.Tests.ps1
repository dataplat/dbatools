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

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $jobName = "dbatoolsci_outputtest_setjob_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description "Test job for output validation"
            $result = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description "Updated description"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Job"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Category",
                "OwnerLoginName",
                "CurrentRunStatus",
                "CurrentRunRetryAttempt",
                "Enabled",
                "LastRunDate",
                "LastRunOutcome",
                "HasSchedule",
                "OperatorToEmail",
                "CreateDate"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $result[0].psobject.Properties["Enabled"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Enabled"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["CreateDate"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["CreateDate"].MemberType | Should -Be "AliasProperty"
        }
    }
}