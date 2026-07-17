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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A stable property-target job for the enable/disable/description assertions, and a
        # separate rename-target job so the destructive rename never disturbs the others.
        $jobName = "dbatoolsci_setjob_$(Get-Random)"
        $renameSrc = "dbatoolsci_rename_$(Get-Random)"
        $renamedName = "dbatoolsci_renamed_$(Get-Random)"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $renameSrc

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = @($jobName, $renameSrc, $renamedName)
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaAgentJob @splatRemove
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Modifying job properties" {
        It "Disables an enabled job" {
            $result = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Disabled
            $result.Enabled | Should -BeFalse
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName).Enabled | Should -BeFalse
        }

        It "Enables a disabled job" {
            $result = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Enabled
            $result.Enabled | Should -BeTrue
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName).Enabled | Should -BeTrue
        }

        It "Sets the job description" {
            $desc = "dbatoolsci description $(Get-Random)"
            $result = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description $desc
            $result.Description | Should -Be $desc
        }

        It "Returns the modified job as an SMO Agent.Job object" {
            # characterization: .OUTPUTS one modified Agent.Job per updated job
            $result = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description "dbatoolsci type check"
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
        }

        It "Accepts a job piped from Get-DbaAgentJob" {
            $desc = "dbatoolsci piped $(Get-Random)"
            $result = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName | Set-DbaAgentJob -Description $desc
            $result.Description | Should -Be $desc
        }
    }

    Context "Renaming" {
        It "Renames the job with -NewName" {
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $renameSrc -NewName $renamedName
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $renamedName).Name | Should -Be $renamedName
            Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $renameSrc -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context "Validation and warnings" {
        It "Warns when neither -Job nor -InputObject is supplied" {
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Set-DbaAgentJob @splatNoTarget 3> $null
            $warn -join " " | Should -Match "must specify a job name or pipe"
        }

        It "Warns for a non-existent job with the current grammar quirk" {
            $splatBadJob = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = "dbatoolsci_nojob_$(Get-Random)"
                Disabled        = $true
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Set-DbaAgentJob @splatBadJob 3> $null
            # characterization: source message reads "doesn't exists" (regex dot for the apostrophe)
            $warn -join " " | Should -Match "doesn.t exists"
        }

        It "Warns setting an unknown category without -Force" {
            $splatBadCat = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Job             = $jobName
                Category        = "dbatoolsci_nocat_$(Get-Random)"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            Set-DbaAgentJob @splatBadCat 3> $null
            $warn -join " " | Should -Match "Use -Force"
        }
    }
}
