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

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $waitingTaskFlag = "dbatools_$(Get-Random)"
        $waitingTaskTime = "00:15:00"
        $waitingTaskSql = "SELECT '$waitingTaskFlag'; WAITFOR DELAY '$waitingTaskTime'"
        $waitingTaskInstance = $TestConfig.InstanceSingle

        $waitingTaskModulePath = (Get-Module -Name dbatools).Path
        $waitingTaskJobName = "YouHaveBeenFoundWaiting"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining processes and jobs
        $waitingTaskProcess = Get-DbaProcess -SqlInstance $waitingTaskInstance | Where-Object Program -eq "dbatools-waiting" | Select-Object -ExpandProperty Spid
        if ($waitingTaskProcess) {
            Stop-DbaProcess -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess -ErrorAction SilentlyContinue

            # I've had a few cases where first run didn't actually kill the process
            $waitingTaskProcessCheck = Get-DbaProcess -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess
            if ($waitingTaskProcessCheck) {
                Stop-DbaProcess -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess -ErrorAction SilentlyContinue
            }
        }
        Get-Job -Name $waitingTaskJobName -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command functionality with waiting task" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Start-Job -Name $waitingTaskJobName -ScriptBlock {
                Import-Module $args[0];
                (Connect-DbaInstance -SqlInstance $args[1] -ClientName dbatools-waiting).ConnectionContext.ExecuteNonQuery($args[2])
            } -ArgumentList $waitingTaskModulePath, $waitingTaskInstance, $waitingTaskSql

            # The job needs some seconds to load the module and to open the connection.
            # On a busy machine this can take more than 30 seconds, so we wait up to 60 seconds and fail loudly instead of continuing with a null spid.
            foreach ($second in 1..60) {
                $waitingTaskProcess = Get-DbaProcess -SqlInstance $waitingTaskInstance | Where-Object Program -eq "dbatools-waiting" | Select-Object -ExpandProperty Spid
                if ($waitingTaskProcess) {
                    break
                }
                Start-Sleep -Seconds 1
            }
            if (-not $waitingTaskProcess) {
                $waitingTaskJobOutput = Get-Job -Name $waitingTaskJobName | Receive-Job -ErrorAction SilentlyContinue | Out-String
                throw "The dbatools-waiting session did not appear on $waitingTaskInstance within 60 seconds. Job output: $waitingTaskJobOutput"
            }

            # The query needs another moment to start, so we poll until the waiting task is reported.
            foreach ($second in 1..30) {
                $results = Get-DbaWaitingTask -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess
                if ($results) {
                    break
                }
                Start-Sleep -Seconds 1
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have correct properties" {
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

        It "Should have command of WAITFOR" {
            $results.WaitType | Should -BeLike "*WAITFOR*"
        }

        It "Should have an InfoUrl for the wait type" {
            $results.InfoUrl | Should -Be "https://www.sqlskills.com/help/waits/WAITFOR"
        }
    }
}