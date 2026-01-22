#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfDataCollector",
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
                "Collector",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command works" {
        It "Returns a result with the right computername and name is not null" {
            $allResults = @()
            $allResults += Get-DbaPfDataCollector | Select-Object -First 1
            $allResults.ComputerName | Should -Be $env:COMPUTERNAME
            $allResults.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollector | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'DataCollectorSet',
                'Name',
                'DataCollectorType',
                'DataSourceName',
                'FileName',
                'FileNameFormat',
                'FileNameFormatPattern',
                'LatestOutputLocation',
                'LogAppend',
                'LogCircular',
                'LogFileFormat',
                'LogOverwrite',
                'SampleInterval',
                'SegmentMaxRecords',
                'Counters'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available via Select-Object" {
            $additionalProps = @(
                'CounterDisplayNames',
                'RemoteLatestOutputLocation',
                'DataCollectorSetXml',
                'CollectorXml',
                'DataCollectorObject',
                'Credential'
            )
            $allProps = ($result | Select-Object *).PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $allProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }

        It "Has DataCollectorObject flag set to true" {
            $result.DataCollectorObject | Should -Be $true
        }
    }
}