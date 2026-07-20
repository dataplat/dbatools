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

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName
        $splatRunningStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $runningJobName
            StepName    = "wait"
            Subsystem   = "TransactSql"
            Command     = "WAITFOR DELAY ${sq}00:02:00${sq}"
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
        try {
            # Best-effort stop: the job can go Idle between any status check and the Stop call,
            # so no check-then-act - the explicit EnableException $false outranks the forced
            # default above and an already-idle failure is swallowed.
            $current = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName -ErrorAction SilentlyContinue
            if ($current) {
                $splatStop = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Job             = $runningJobName
                    Wait            = $true
                    EnableException = $false
                    ErrorAction     = "SilentlyContinue"
                    WarningAction   = "SilentlyContinue"
                }
                $null = Stop-DbaAgentJob @splatStop
            }
        } finally {
            # Inner try/finally: the removal can still throw under the forced EnableException,
            # so the default-parameter restoration lives in the innermost finally and always runs.
            try {
                $splatRemove = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Job         = @($runningJobName, $idleJobName)
                    ErrorAction = "SilentlyContinue"
                }
                $null = Remove-DbaAgentJob @splatRemove
            } finally {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    Context "When a job is executing" {
        It "Returns the executing job and never an Idle one" {
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            # The running job must be present (non-vacuous), and no returned job is Idle.
            $results.Name | Should -Contain $runningJobName
            ($results.CurrentRunStatus | Where-Object { $PSItem -eq "Idle" }) | Should -BeNullOrEmpty
        }

        It "Does not return the idle job" {
            $results = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Not -Contain $idleJobName
        }

        It "Returns the executing job as an SMO Agent.Job object" {
            # characterization: output is the SMO Agent.Job surface (Get-DbaAgentJob passthrough)
            $result = Get-DbaRunningJob -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $runningJobName
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
        }

        It "Filters piped Agent.Job input to only the running ones" {
            # Scoped to the two fixture jobs: piping every job on the shared instance exposes
            # the assertion to unrelated job churn from concurrent suites.
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $runningJobName, $idleJobName | Get-DbaRunningJob
            $results.Name | Should -Contain $runningJobName
            $results.Name | Should -Not -Contain $idleJobName
        }
    }

    Context "When the piped job is not executing" {
        It "Returns nothing for an idle job piped in" {
            # characterization: an Idle job through -InputObject yields no output at all.
            $idleJob = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $idleJobName
            $idleJob | Get-DbaRunningJob | Should -BeNullOrEmpty
        }
    }

    Context "Against an unreachable instance" {
        It "Warns and continues without EnableException" {
            $splatBad = @{
                SqlInstance     = "dbatoolsci_nope_$(Get-Random)"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $null = Get-DbaRunningJob @splatBad 3> $null
            $warn | Should -Not -BeNullOrEmpty
        }
    }
}
