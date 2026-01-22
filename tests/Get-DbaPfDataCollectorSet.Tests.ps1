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
        It "Returns a result with the right computername and name is not null" {
            $results = @(Get-DbaPfDataCollectorSet | Select-Object -First 1)
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorSet | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'Name',
                'DisplayName',
                'Description',
                'State',
                'Duration',
                'OutputLocation',
                'LatestOutputLocation',
                'RootPath',
                'SchedulesEnabled',
                'Segment',
                'SegmentMaxDuration',
                'SegmentMaxSize',
                'SerialNumber',
                'Server',
                'StopOnCompletion',
                'Subdirectory',
                'SubdirectoryFormat',
                'SubdirectoryFormatPattern',
                'Task',
                'TaskArguments',
                'TaskRunAsSelf',
                'TaskUserTextArguments',
                'UserAccount'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected additional properties" {
            $additionalProps = @(
                'Keywords',
                'DescriptionUnresolved',
                'DisplayNameUnresolved',
                'Schedules',
                'Xml',
                'Security',
                'DataCollectorSetObject',
                'TaskObject',
                'Credential'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available via Select-Object *"
            }
        }
    }
}