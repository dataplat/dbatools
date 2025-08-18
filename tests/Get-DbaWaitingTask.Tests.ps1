#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWaitingTask",
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
                "Spid",
                "IncludeSystemSpid",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $global:waitingTaskFlag = "dbatools_$(Get-Random)"
        $global:waitingTaskTime = "00:15:00"
        $global:waitingTaskSql = "SELECT '$global:waitingTaskFlag'; WAITFOR DELAY '$global:waitingTaskTime'"
        $global:waitingTaskInstance = $TestConfig.instance2

        $global:waitingTaskModulePath = "C:\Github\dbatools\dbatools.psm1"
        $global:waitingTaskJobName = "YouHaveBeenFoundWaiting"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining processes and jobs
        $global:waitingTaskProcess = Get-DbaProcess -SqlInstance $global:waitingTaskInstance | Where-Object Program -eq "dbatools-waiting" | Select-Object -ExpandProperty Spid
        if ($global:waitingTaskProcess) {
            Stop-DbaProcess -SqlInstance $global:waitingTaskInstance -Spid $global:waitingTaskProcess -ErrorAction SilentlyContinue

            # I've had a few cases where first run didn't actually kill the process
            $global:waitingTaskProcessCheck = Get-DbaProcess -SqlInstance $global:waitingTaskInstance -Spid $global:waitingTaskProcess
            if ($global:waitingTaskProcessCheck) {
                Stop-DbaProcess -SqlInstance $global:waitingTaskInstance -Spid $global:waitingTaskProcess -ErrorAction SilentlyContinue
            }
        }
        Get-Job -Name $global:waitingTaskJobName -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    }

    Context "Command functionality with waiting task" {
        BeforeAll {
            Start-Job -Name $global:waitingTaskJobName -ScriptBlock {
                Import-Module $args[0];
                (Connect-DbaInstance -SqlInstance $args[1] -ClientName dbatools-waiting).Query($args[2])
            } -ArgumentList $global:waitingTaskModulePath, $global:waitingTaskInstance, $global:waitingTaskSql

            <#
                **This has to sleep as it can take a couple seconds for the job to start**
                Setting it lower will cause issues, you have to consider the Start-Job has to load the module which takes on average 3-4 seconds itself before it executes the command.

                If someone knows a cleaner method by all means adjust this test.
            #>
            Start-Sleep -Seconds 8

            $global:waitingTaskProcess = Get-DbaProcess -SqlInstance $global:waitingTaskInstance | Where-Object Program -eq "dbatools-waiting" | Select-Object -ExpandProperty Spid
        }

        It "Should have correct properties" -Skip:($null -eq $global:waitingTaskProcess) {
            $results = Get-DbaWaitingTask -SqlInstance $global:waitingTaskInstance -Spid $global:waitingTaskProcess
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Spid",
                "Thread",
                "Scheduler",
                "WaitMs",
                "WaitType",
                "BlockingSpid",
                "ResourceDesc",
                "NodeId",
                "Dop",
                "DbId",
                "InfoUrl",
                "QueryPlan",
                "SqlText"
            )
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should have command of WAITFOR" -Skip:($null -eq $global:waitingTaskProcess) {
            $results = Get-DbaWaitingTask -SqlInstance $global:waitingTaskInstance -Spid $global:waitingTaskProcess
            $results.WaitType | Should -BeLike "*WAITFOR*"
        }
    }
}