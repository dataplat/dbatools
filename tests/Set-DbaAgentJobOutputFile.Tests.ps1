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

        # A single named step targeted explicitly by -Step, which avoids the multi-step
        # Out-GridView interactive path (untestable) and keeps every assertion deterministic.
        $jobName = "dbatoolsci_outfile_$(Get-Random)"
        $stepName = "outstep"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $splatStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            StepName    = $stepName
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep

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

    Context "Setting the output file" {
        It "Sets the output file and returns the change" {
            $outFile = "C:\temp\dbatoolsci_$(Get-Random).txt"
            $splatSet = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = $outFile
            }
            $result = Set-DbaAgentJobOutputFile @splatSet
            $result.Job | Should -Be $jobName
            $result.JobStep | Should -Be $stepName
            $result.OutputFileName | Should -Be $outFile
            # And the change persists on the step itself.
            (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName $stepName).OutputFileName | Should -Be $outFile
        }

        It "Reports the previous file in OldOutputFileName on a re-set" {
            # Establish a known baseline, then change it - OldOutputFileName must echo the baseline.
            $baseline = "C:\temp\dbatoolsci_base_$(Get-Random).txt"
            $updated = "C:\temp\dbatoolsci_new_$(Get-Random).txt"
            $splatBase = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = $baseline
            }
            $null = Set-DbaAgentJobOutputFile @splatBase
            $splatUpdate = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = $updated
            }
            $result = Set-DbaAgentJobOutputFile @splatUpdate
            $result.OldOutputFileName | Should -Be $baseline
            $result.OutputFileName | Should -Be $updated
        }
    }

    Context "WhatIf" {
        It "Does not change the output file under -WhatIf" {
            # Set a known value, then a -WhatIf attempt must neither change it nor emit output.
            $known = "C:\temp\dbatoolsci_known_$(Get-Random).txt"
            $splatKnown = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = $known
            }
            $null = Set-DbaAgentJobOutputFile @splatKnown
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Step        = $stepName
                OutputFile  = "C:\temp\dbatoolsci_nope_$(Get-Random).txt"
                WhatIf      = $true
            }
            $result = Set-DbaAgentJobOutputFile @splatWhatIf
            $result | Should -BeNullOrEmpty
            (Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName $stepName).OutputFileName | Should -Be $known
        }
    }

    Context "Validation and warnings" {
        It "Warns when -Job is omitted" {
            $splatNoJob = @{
                SqlInstance     = $TestConfig.InstanceSingle
                OutputFile      = "C:\temp\dbatoolsci_$(Get-Random).txt"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Set-DbaAgentJobOutputFile @splatNoJob 3> $null
            $warn -join " " | Should -Match "must specify a job"
        }

        It "Warns when -Step matches no step" {
            $splatBadStep = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $jobName
                Step            = "dbatoolsci_nostep_$(Get-Random)"
                OutputFile      = "C:\temp\dbatoolsci_$(Get-Random).txt"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Set-DbaAgentJobOutputFile @splatBadStep 3> $null
            # characterization: source reads "$Step didn't return any steps" (regex dot for the apostrophe)
            $warn -join " " | Should -Match "didn.t return any steps"
        }
    }
}
