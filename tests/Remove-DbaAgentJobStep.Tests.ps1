#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobStep",
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
                "StepName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # One job carrying several distinct steps, so each destructive assertion targets its own
        # step and the surviving steps prove the removal is surgical.
        $jobName = "dbatoolsci_rmstep_$(Get-Random)"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        foreach ($step in "step_remove", "step_keep", "step_whatif", "step_nooutput") {
            $splatStep = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                StepName    = $step
                Subsystem   = "TransactSql"
                Command     = "SELECT 1"
            }
            $null = New-DbaAgentJobStep @splatStep
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        # Values baked into the child-host guard probes below. The probe scripts are generated with
        # these already interpolated, so the generated file carries no variables of its own.
        # Round 2 (A re-gate 2026-07-19): (Get-Module dbatools).Path resolved to the GALLERY module
        # under the gate, and the child's Import-Module of it failed - reddening both guard legs on the
        # import error instead of the characterized warning. Per A's route, the child must use the
        # dev-tree convention: the dev-tree modules dir prepended to PSModulePath (the child inherits
        # this process env) and the dev-tree root module imported by explicit path.
        $devTreeModule = "C:\github\dbatools\dbatools.psm1"
        $script:savedPSModulePath = $env:PSModulePath
        $env:PSModulePath = "C:\github\dbatools\modules;$env:PSModulePath"
        $probeInstance = $TestConfig.InstanceSingle
        # launch the child on the SAME host executable as this run, so the guard is exercised on the
        # edition the gate is currently running (Desktop or Core)
        $probeHost = (Get-Process -Id $PID).Path
    }

    AfterAll {
        $env:PSModulePath = $script:savedPSModulePath
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaAgentJob @splatRemove
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Removing an existing step" {
        It "Removes only the named step and leaves the others" {
            $splatRemoveStep = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                StepName    = "step_remove"
            }
            Remove-DbaAgentJobStep @splatRemoveStep
            $steps = (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName).Name
            $steps | Should -Not -Contain "step_remove"
            $steps | Should -Contain "step_keep"
        }

        It "Returns no output" {
            # characterization: .OUTPUTS None - the removal emits nothing to the pipeline. Uses its
            # own step so it never disturbs a step another test asserts on (order-independent).
            $splatRemoveStep = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                StepName    = "step_nooutput"
            }
            $result = Remove-DbaAgentJobStep @splatRemoveStep
            $result | Should -BeNullOrEmpty
        }
    }

    Context "WhatIf" {
        It "Does not remove the step under -WhatIf" {
            Remove-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName "step_whatif" -WhatIf
            $steps = (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName).Name
            $steps | Should -Contain "step_whatif"
        }
    }

    Context "When the target does not exist" {
        # WHY THESE TWO RUN IN A CHILD HOST: both guards below reach
        # Stop-Function -Continue -ContinueLabel main, but the source defines no :main label
        # anywhere. PowerShell resolves the unmatched continue against whatever enclosing loops the
        # HOST happens to have, which inside Pester unwinds the iteration of the runner itself and tears the
        # session down silently with exit code 0 - producing a gate run with no artifact at all
        # (confirmed on both editions by the integrator gate). Asserting these guards in-process is
        # therefore structurally impossible, not merely awkward. Each guard is instead exercised in a
        # child host whose warning stream is merged into stdout, and the behavior is asserted from
        # outside: the warning text proves the guard fired, and the child exiting 0 with the command
        # having emitted nothing further is the observable signature of the dangling-label unwind.

        It "Warns for a non-existent job without EnableException" {
            $badJob = "dbatoolsci_nojob_$(Get-Random)"
            $probeFile = Join-Path $env:TEMP "dbatoolsci_rmstep_nojob_$([guid]::NewGuid()).ps1"
            # generated with the values already interpolated, so the probe holds no variables
            $probeBody = @"
Import-Module "$devTreeModule" -ErrorAction Stop
Remove-DbaAgentJobStep -SqlInstance "$probeInstance" -Job "$badJob" -StepName "step_whatif" 3>&1
"@
            Set-Content -Path $probeFile -Value $probeBody
            try {
                $captured = & $probeHost -NoProfile -File $probeFile 2>&1 | Out-String
                $childExit = $LASTEXITCODE

                # characterization: the missing-job message carries the current doesnn-t typo
                # (regex dot stands in for the apostrophe).
                $captured | Should -Match "doesnn.t exist"
                # the dangling-label unwind ends the child quietly rather than faulting it
                $childExit | Should -Be 0
            } finally {
                Remove-Item -Path $probeFile -ErrorAction SilentlyContinue
            }
        }

        It "Warns for a non-existent step without EnableException" {
            $badStep = "dbatoolsci_nostep_$(Get-Random)"
            $probeFile = Join-Path $env:TEMP "dbatoolsci_rmstep_nostep_$([guid]::NewGuid()).ps1"
            $probeBody = @"
Import-Module "$devTreeModule" -ErrorAction Stop
Remove-DbaAgentJobStep -SqlInstance "$probeInstance" -Job "$jobName" -StepName "$badStep" 3>&1
"@
            Set-Content -Path $probeFile -Value $probeBody
            try {
                $captured = & $probeHost -NoProfile -File $probeFile 2>&1 | Out-String
                $childExit = $LASTEXITCODE

                $captured | Should -Match "doesn.t exist for"
                $childExit | Should -Be 0
            } finally {
                Remove-Item -Path $probeFile -ErrorAction SilentlyContinue
            }
        }
    }
}
