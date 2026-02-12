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

    Context "Command functionality with waiting task" {
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
            $results = Get-DbaWaitingTask -SqlInstance $waitingTaskInstance -Spid $waitingTaskProcess
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

        It "Returns output of the expected type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Spid", "Thread", "Scheduler", "WaitMs", "WaitType", "BlockingSpid", "ResourceDesc", "NodeId", "Dop", "DbId")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include excluded properties in default display" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "SqlText" -Because "SqlText is excluded via Select-DefaultView"
            $defaultProps | Should -Not -Contain "QueryPlan" -Because "QueryPlan is excluded via Select-DefaultView"
            $defaultProps | Should -Not -Contain "InfoUrl" -Because "InfoUrl is excluded via Select-DefaultView"
        }

        It "Has the excluded properties available on the object" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].PSObject.Properties.Name | Should -Contain "SqlText" -Because "SqlText should be accessible via Select-Object *"
            $results[0].PSObject.Properties.Name | Should -Contain "QueryPlan" -Because "QueryPlan should be accessible via Select-Object *"
            $results[0].PSObject.Properties.Name | Should -Contain "InfoUrl" -Because "InfoUrl should be accessible via Select-Object *"
        }
    }
}