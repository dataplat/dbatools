#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorSet",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command works" {
        BeforeAll {
            $script:outputForValidation = @(Get-DbaPfDataCollectorSet | Select-Object -First 1)
        }

        It "Returns a result with the right computername and name is not null" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no data collector sets found on this system" }
            $script:outputForValidation.ComputerName | Should -Be $env:COMPUTERNAME
            $script:outputForValidation.Name | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no data collector sets found on this system" }
            $script:outputForValidation[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no data collector sets found on this system" }
            $defaultProps = $script:outputForValidation[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
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
    }
}