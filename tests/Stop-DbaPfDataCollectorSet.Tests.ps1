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

    Context -Skip:(-not (Get-DbaPfDataCollectorSet -CollectorSet RTEvents)) "Output Validation" {
        BeforeAll {
            # Ensure collector is running before stopping
            $null = Start-DbaPfDataCollectorSet -CollectorSet RTEvents -EnableException
            $result = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents -EnableException
        }

        AfterAll {
            # Restart the collector for other tests
            $null = Start-DbaPfDataCollectorSet -CollectorSet RTEvents
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "Name",
                "DisplayName",
                "Description",
                "State",
                "Duration",
                "OutputLocation",
                "LatestOutputLocation",
                "RootPath",
                "SchedulesEnabled",
                "Segment",
                "SegmentMaxDuration",
                "SegmentMaxSize",
                "SerialNumber",
                "Server",
                "StopOnCompletion",
                "Subdirectory",
                "SubdirectoryFormat",
                "SubdirectoryFormatPattern",
                "Task",
                "TaskArguments",
                "TaskRunAsSelf",
                "TaskUserTextArguments",
                "UserAccount"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties accessible via Select-Object *" {
            $additionalProps = @(
                "Keywords",
                "DescriptionUnresolved",
                "DisplayNameUnresolved",
                "RemoteOutputLocation",
                "RemoteLatestOutputLocation",
                "Schedules",
                "Xml",
                "Security",
                "Status",
                "DataCollectorSetObject",
                "TaskObject",
                "Credential"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "additional property '$prop' should be accessible"
            }
        }

        It "State property reflects stopped status" {
            $result.State | Should -BeIn @("Ready", "Stopped", "Unknown") -Because "collector set should be stopped after Stop-DbaPfDataCollectorSet"
        }

        It "DataCollectorSetObject property is set to true" {
            $result.DataCollectorSetObject | Should -Be $true
        }
    }
}
