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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a job that runs long enough to stop
            $outputJobName = "dbatoolsci_stopjob_output_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -StepName "WaitStep" -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName
            Start-Sleep -Milliseconds 500
            $outputResult = Stop-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -Wait

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Job"
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].Name | Should -Be $outputJobName
            $outputResult[0].PSObject.Properties.Name | Should -Contain "CurrentRunStatus"
            $outputResult[0].PSObject.Properties.Name | Should -Contain "LastRunOutcome"
            $outputResult[0].PSObject.Properties.Name | Should -Contain "IsEnabled"
        }
    }
}