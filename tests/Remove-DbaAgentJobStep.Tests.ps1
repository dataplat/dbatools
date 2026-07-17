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
    }

    AfterAll {
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
        It "Warns for a non-existent job without EnableException" {
            $splatBadJob = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = "dbatoolsci_nojob_$(Get-Random)"
                StepName        = "step_whatif"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Remove-DbaAgentJobStep @splatBadJob 3> $null
            # characterization: the missing-job message carries the current doesnn-t typo
            # (regex dot stands in for the apostrophe).
            $warn -join " " | Should -Match "doesnn.t exist"
        }

        It "Warns for a non-existent step without EnableException" {
            $splatBadStep = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $jobName
                StepName        = "dbatoolsci_nostep_$(Get-Random)"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Remove-DbaAgentJobStep @splatBadStep 3> $null
            $warn -join " " | Should -Match "doesn.t exist for"
        }
    }
}
