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
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $jobName = "dbatoolsci_runningjob_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName "Step1" -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            Start-Sleep -Seconds 3
            $result = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Stop-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no running jobs found" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Job"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no running jobs found" }
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
            if (-not $result) { Set-ItResult -Skipped -Because "no running jobs found" }
            $result[0].psobject.Properties["Enabled"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Enabled"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["CreateDate"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["CreateDate"].MemberType | Should -Be "AliasProperty"
        }
    }
}