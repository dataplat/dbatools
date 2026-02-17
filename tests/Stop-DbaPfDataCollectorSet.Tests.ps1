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
            $results = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents -OutVariable "global:dbatoolsciOutput"

            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $expectedProperties = @(
                "ComputerName",
                "Name",
                "LatestOutputLocation",
                "OutputLocation",
                "RemoteOutputLocation",
                "RemoteLatestOutputLocation",
                "RootPath",
                "Duration",
                "Description",
                "DescriptionUnresolved",
                "DisplayName",
                "DisplayNameUnresolved",
                "Keywords",
                "Segment",
                "SegmentMaxDuration",
                "SegmentMaxSize",
                "SerialNumber",
                "Server",
                "Status",
                "Subdirectory",
                "SubdirectoryFormat",
                "SubdirectoryFormatPattern",
                "Task",
                "TaskRunAsSelf",
                "TaskArguments",
                "TaskUserTextArguments",
                "Schedules",
                "SchedulesEnabled",
                "UserAccount",
                "Xml",
                "Security",
                "StopOnCompletion",
                "State",
                "DataCollectorSetObject",
                "TaskObject",
                "Credential"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
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
