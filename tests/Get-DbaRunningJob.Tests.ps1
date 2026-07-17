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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A long-running job (WAITFOR DELAY) is the deterministic way to observe a job in a
        # non-Idle CurrentRunStatus; an unstarted job stays Idle and characterizes the filter.
        # [char]39 builds the T-SQL time literal's required apostrophes without a PS single-quoted token.
        $sq = [string][char]39
        $runningJobName = "dbatoolsci_running_$(Get-Random)"
        $idleJobName = "dbatoolsci_idle_$(Get-Random)"
        $waitCommand = "WAITFOR DELAY ${sq}00:00:30${sq}"

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName
        $splatRunningStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $runningJobName
            StepName    = "wait"
            Subsystem   = "TransactSql"
            Command     = $waitCommand
        }
        $null = New-DbaAgentJobStep @splatRunningStep

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $idleJobName
        $splatIdleStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $idleJobName
            StepName    = "noop"
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatIdleStep

        # Start the long job without waiting so it is mid-flight for the assertions below.
        $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Stop-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName, $idleJobName -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When jobs are executing" {
        It "Returns the currently executing job" {
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Contain $runningJobName
        }

        It "Every returned job is non-Idle" {
            # characterization: the command filters out CurrentRunStatus -eq "Idle"
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            ($results.CurrentRunStatus | Where-Object { $PSItem -eq "Idle" }) | Should -BeNullOrEmpty
        }

        It "Does not return an idle job" {
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Not -Contain $idleJobName
        }

        It "Returns SMO Agent.Job objects" {
            # characterization: output is the SMO Agent.Job surface (Get-DbaAgentJob passthrough)
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            $results | Select-Object -First 1 | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
        }

        It "Filters piped Agent.Job input to only the running ones" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle | Get-DbaRunningJob
            $results.Name | Should -Contain $runningJobName
            $results.Name | Should -Not -Contain $idleJobName
        }
    }

    Context "When nothing is executing" {
        It "Returns nothing once the job has stopped" {
            $null = Stop-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName -ErrorAction SilentlyContinue
            # Poll briefly for the stop to settle, then characterize the empty result.
            $deadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Seconds 2
                $stillRunning = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $runningJobName
            } while ($stillRunning -and (Get-Date) -lt $deadline)
            $stillRunning | Should -BeNullOrEmpty
        }
    }

    Context "Against an unreachable instance" {
        It "Warns and continues without EnableException" {
            $null = Get-DbaRunningJob -SqlInstance "dbatoolsci_nope_$(Get-Random)" -WarningAction SilentlyContinue -WarningVariable warn 3> $null
            $warn | Should -Not -BeNullOrEmpty
        }
    }
}
