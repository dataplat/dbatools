#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobOutputFile",
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
                "Step",
                "OutputFile",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Each job carries a single step so the multi-step Out-GridView interactive path is
        # never reached; separate jobs keep the destructive assertions from interfering.
        # $jobMain  - the -Step-targeted re-set / whatif / bad-step tests
        # $jobFresh - the never-touched-before "returned contract" test (proves OldOutputFileName="")
        # $jobNoStep - the -Step-omitted single-step auto-selection test
        $stepName = "outstep"
        $jobMain = "dbatoolsci_outfile_$(Get-Random)"
        $jobFresh = "dbatoolsci_outfile_fresh_$(Get-Random)"
        $jobNoStep = "dbatoolsci_outfile_nostep_$(Get-Random)"

        foreach ($j in $jobMain, $jobFresh, $jobNoStep) {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $j
            $splatStep = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $j
                StepName    = $stepName
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
                Job         = @($jobMain, $jobFresh, $jobNoStep)
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaAgentJob @splatRemove
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "The returned object" {
        It "Returns every documented property, with an empty OldOutputFileName on a fresh step" {
            $outFile = "C:\temp\dbatoolsci_$(Get-Random).txt"
            $splatSet = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobFresh
                Step        = $stepName
                OutputFile  = $outFile
            }
            $result = Set-DbaAgentJobOutputFile @splatSet
            $result.PSObject.Properties.Name | Should -Contain "ComputerName"
            $result.PSObject.Properties.Name | Should -Contain "InstanceName"
            $result.PSObject.Properties.Name | Should -Contain "SqlInstance"
            $result.PSObject.Properties.Name | Should -Contain "Job"
            $result.PSObject.Properties.Name | Should -Contain "JobStep"
            $result.PSObject.Properties.Name | Should -Contain "OutputFileName"
            $result.PSObject.Properties.Name | Should -Contain "OldOutputFileName"
            $result.Job | Should -Be $jobFresh
            $result.JobStep | Should -Be $stepName
            $result.OutputFileName | Should -Be $outFile
            # characterization: a step with no prior output file reports an empty OldOutputFileName
            $result.OldOutputFileName | Should -Be ""
        }
    }

    Context "Setting the output file" {
        It "Reports the previous file in OldOutputFileName and persists the new one on a re-set" {
            $baseline = "C:\temp\dbatoolsci_base_$(Get-Random).txt"
            $updated = "C:\temp\dbatoolsci_new_$(Get-Random).txt"
            $splatBase = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobMain
                Step        = $stepName
                OutputFile  = $baseline
            }
            $null = Set-DbaAgentJobOutputFile @splatBase
            $splatUpdate = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobMain
                Step        = $stepName
                OutputFile  = $updated
            }
            $result = Set-DbaAgentJobOutputFile @splatUpdate
            $result.OldOutputFileName | Should -Be $baseline
            $result.OutputFileName | Should -Be $updated
            (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobMain -StepName $stepName).OutputFileName | Should -Be $updated
        }

        It "Sets the only step when -Step is omitted" {
            # A single-step job takes the automatic-selection branch (no interactive Out-GridView).
            $outFile = "C:\temp\dbatoolsci_nostep_$(Get-Random).txt"
            $splatNoStep = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobNoStep
                OutputFile  = $outFile
            }
            $result = Set-DbaAgentJobOutputFile @splatNoStep
            $result.JobStep | Should -Be $stepName
            $result.OutputFileName | Should -Be $outFile
            (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobNoStep -StepName $stepName).OutputFileName | Should -Be $outFile
        }
    }

    Context "WhatIf" {
        It "Does not change the output file under -WhatIf" {
            $known = "C:\temp\dbatoolsci_known_$(Get-Random).txt"
            $splatKnown = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobMain
                Step        = $stepName
                OutputFile  = $known
            }
            $null = Set-DbaAgentJobOutputFile @splatKnown
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobMain
                Step        = $stepName
                OutputFile  = "C:\temp\dbatoolsci_nope_$(Get-Random).txt"
                WhatIf      = $true
            }
            $result = Set-DbaAgentJobOutputFile @splatWhatIf
            $result | Should -BeNullOrEmpty
            (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobMain -StepName $stepName).OutputFileName | Should -Be $known
        }
    }

    Context "Validation and warnings" {
        It "Warns and emits nothing when -Job is omitted" {
            $splatNoJob = @{
                SqlInstance     = $TestConfig.InstanceSingle
                OutputFile      = "C:\temp\dbatoolsci_$(Get-Random).txt"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $result = Set-DbaAgentJobOutputFile @splatNoJob 3> $null
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "You must specify a job using the -Job parameter"
        }

        It "Warns and emits nothing when -Step matches no step" {
            $badStep = "dbatoolsci_nostep_$(Get-Random)"
            $splatBadStep = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $jobMain
                Step            = $badStep
                OutputFile      = "C:\temp\dbatoolsci_$(Get-Random).txt"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $result = Set-DbaAgentJobOutputFile @splatBadStep 3> $null
            $result | Should -BeNullOrEmpty
            # characterization: source reads "$Step didn't return any steps" (regex dot for apostrophe)
            $warn -join " " | Should -Match "$badStep didn.t return any steps"
        }
    }
}
