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

        # Clean up any existing collector sets before starting
        $null = Get-DbaPfDataCollectorSet -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $null = Get-DbaPfDataCollectorSet -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Get-DbaPfDataCollectorSet -CollectorSet $collectorSetName | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command returns all the required results with pipe" {
        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template $collectorSetName | Import-DbaPfDataCollectorSetTemplate
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It "returns only one (and the proper) template without pipe" {
            $results = Import-DbaPfDataCollectorSetTemplate -Template $collectorSetName
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }
    }
}