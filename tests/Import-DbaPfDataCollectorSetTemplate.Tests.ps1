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
    }
}

Describe "$CommandName Output" -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

            $outputCollectorSetName = "Long Running Queries"
            $outputComputerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName

            $null = Get-DbaPfDataCollectorSet -ComputerName $outputComputerName -CollectorSet $outputCollectorSetName | Remove-DbaPfDataCollectorSet

            $outputResult = Import-DbaPfDataCollectorSetTemplate -ComputerName $outputComputerName -Template $outputCollectorSetName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

            $null = Get-DbaPfDataCollectorSet -ComputerName $outputComputerName -CollectorSet $outputCollectorSetName | Remove-DbaPfDataCollectorSet -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $PSDefaultParameterValues.Remove("*-Dba*:Confirm")
        }

        It "Returns output of the documented type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
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
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].Name | Should -Be $outputCollectorSetName
            $outputResult[0].ComputerName | Should -Be $outputComputerName
        }
    }
}