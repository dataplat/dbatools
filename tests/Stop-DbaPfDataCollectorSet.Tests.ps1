#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "InputObject",
                "NoWait",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context -Skip:(-not (Get-DbaPfDataCollectorSet -CollectorSet RTEvents)) "Verifying command works" {
        AfterAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We only run this on Azure as there is this collector set running:
            $null = Start-DbaPfDataCollectorSet -CollectorSet RTEvents

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns a result with the right computername and name is not null" {
            $results = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents

            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Use the pre-existing dbatoolsci_PerfOutput collector set
            $collectorSetName = "dbatoolsci_PerfOutput"
            try {
                $null = Start-DbaPfDataCollectorSet -CollectorSet $collectorSetName -ErrorAction Stop
                Start-Sleep -Seconds 2
                $result = Stop-DbaPfDataCollectorSet -CollectorSet $collectorSetName
            } catch {
                $result = $null
            }
        }

        It "Returns output with expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate - collector set may not be available" }
            $result[0].PSObject.Properties.Name | Should -Contain "ComputerName"
            $result[0].PSObject.Properties.Name | Should -Contain "Name"
            $result[0].PSObject.Properties.Name | Should -Contain "State"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate - collector set may not be available" }
            $expectedDefaults = @("ComputerName", "Name", "DisplayName", "Description", "State", "Duration", "OutputLocation", "LatestOutputLocation", "RootPath", "SchedulesEnabled", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "StopOnCompletion", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskArguments", "TaskRunAsSelf", "TaskUserTextArguments", "UserAccount")
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}
