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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.InstanceSingle

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command works" {
        It "Returns a result with the right computername and name is not null" {
            $allResults = @()
            $allResults += Get-DbaPfDataCollector | Select-Object -First 1
            $allResults.ComputerName | Should -Be $env:COMPUTERNAME
            $allResults.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollector -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" | Select-Object -First 1
        }

        It "Returns output as PSCustomObject" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "DataCollectorSet",
                "Name",
                "DataCollectorType",
                "DataSourceName",
                "FileName",
                "FileNameFormat",
                "FileNameFormatPattern",
                "LatestOutputLocation",
                "LogAppend",
                "LogCircular",
                "LogFileFormat",
                "LogOverwrite",
                "SampleInterval",
                "SegmentMaxRecords",
                "Counters"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}