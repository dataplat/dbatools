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
            $results = Import-DbaPfDataCollectorSetTemplate -ComputerName $computerName -Template $collectorSetName -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be $collectorSetName
            $results.ComputerName | Should -Be $computerName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}