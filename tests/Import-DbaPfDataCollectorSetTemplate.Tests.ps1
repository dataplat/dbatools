#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaPfDataCollectorSetTemplate",
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
                "DisplayName",
                "SchedulesEnabled",
                "RootPath",
                "Segment",
                "SegmentMaxDuration",
                "SegmentMaxSize",
                "Subdirectory",
                "SubdirectoryFormat",
                "SubdirectoryFormatPattern",
                "Task",
                "TaskRunAsSelf",
                "TaskArguments",
                "TaskUserTextArguments",
                "StopOnCompletion",
                "Path",
                "Template",
                "Instance",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $collectorSetName = "Long Running Queries"

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
        # Clean up any existing collector sets before starting
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Get-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command returns all the required results with pipe" {
        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template $collectorSetName | Import-DbaPfDataCollectorSetTemplate -ComputerName $computerName
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $computerName
        }

        It "returns only one (and the proper) template without pipe" {
            $results = Import-DbaPfDataCollectorSetTemplate -ComputerName $computerName -Template $collectorSetName
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $computerName
        }

        It "Returns output of the documented type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
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
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has correct Name and ComputerName values" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].Name | Should -Be $collectorSetName
            $results[0].ComputerName | Should -Be $computerName
        }
    }
}