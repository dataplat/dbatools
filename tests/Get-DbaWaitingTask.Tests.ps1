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

        $waitingTaskModulePath = "C:\Github\dbatools\dbatools.psm1"
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

    Context "Output Validation" {
        BeforeAll {
            Start-Job -Name $waitingTaskJobName -ScriptBlock {
                Import-Module $args[0];
                (Connect-DbaInstance -SqlInstance $args[1] -ClientName dbatools-waiting).ConnectionContext.ExecuteNonQuery($args[2])
            } -ArgumentList $waitingTaskModulePath, $waitingTaskInstance, $waitingTaskSql

            # The job needs some seconds to load the module and to open the connection
            foreach ($second in 1..30) {
                $waitingTaskProcess = Get-DbaProcess -SqlInstance $waitingTaskInstance | Where-Object Program -eq "dbatools-waiting" | Select-Object -ExpandProperty Spid
                if ($waitingTaskProcess) {
                    break
                }
                Start-Sleep -Seconds 1
            }

            # Wait another second for the query to start
            Start-Sleep -Seconds 1

            # Get the results
            $results = Get-DbaWaitingTask -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess -EnableException
        }

        It "Returns PSCustomObject" {
            $results.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Spid',
                'Thread',
                'Scheduler',
                'WaitMs',
                'WaitType',
                'BlockingSpid',
                'ResourceDesc',
                'NodeId',
                'Dop',
                'DbId'
            )
            $actualProps = $results.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available via Select-Object" {
            $additionalProps = @('SqlText', 'QueryPlan', 'InfoUrl')
            $actualProps = $results.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available but excluded from default display"
            }
        }

        It "Returns waiting task data" {
            $results.WaitType | Should -BeLike "*WAITFOR*"
        }
    }
}