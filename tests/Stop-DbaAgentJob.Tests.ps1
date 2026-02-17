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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_stopjob_$(Get-Random)"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobName
        $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti2 -Job $jobName -StepName "step1_$(Get-Random)" -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"

        # Start the job so we can stop it
        $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobName
        Start-Sleep -Milliseconds 500

        $stopResults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobName | Stop-DbaAgentJob -OutVariable "global:dbatoolsciOutput"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command execution and functionality" {
        It "Should stop an agent job and return CurrentRunStatus of Idle" {
            $stopResults.CurrentRunStatus | Should -Be "Idle"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Job"
        }
    }
}