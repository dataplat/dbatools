#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaPfDataCollectorSet",
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
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We only run this on Azure as there is this collector set running:
            $null = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns a result with the right computername and name is not null" {
            $results = Start-DbaPfDataCollectorSet -CollectorSet RTEvents

            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Clean up any leftover from previous runs
            $null = Stop-DbaPfDataCollectorSet -CollectorSet "dbatoolsci_PerfOutput" -ErrorAction SilentlyContinue
            try { $null = Remove-DbaPfDataCollectorSet -CollectorSet "dbatoolsci_PerfOutput" -ErrorAction SilentlyContinue } catch { }

            # Create a collector set using COM object with XML
            $pfXml = @"
<DataCollectorSet>
    <Status>0</Status>
    <Duration>0</Duration>
    <Description>dbatools CI test collector set</Description>
    <DisplayName>dbatoolsci_PerfOutput</DisplayName>
    <SchedulesEnabled>0</SchedulesEnabled>
    <Name>dbatoolsci_PerfOutput</Name>
    <RootPath>%systemdrive%\PerfLogs\Admin</RootPath>
    <SubdirectoryFormat>3</SubdirectoryFormat>
    <SubdirectoryFormatPattern>yyyyMMdd\-NNNNNN</SubdirectoryFormatPattern>
    <UserAccount>SYSTEM</UserAccount>
    <StopOnCompletion>0</StopOnCompletion>
    <PerformanceCounterDataCollector>
        <DataCollectorType>0</DataCollectorType>
        <Name>dbatoolsci_Counter</Name>
        <FileName>dbatoolsci_Counter</FileName>
        <SampleInterval>15</SampleInterval>
        <LogFileFormat>3</LogFileFormat>
        <Counter>\Processor(_Total)\% Processor Time</Counter>
        <CounterDisplayName>\Processor(_Total)\% Processor Time</CounterDisplayName>
    </PerformanceCounterDataCollector>
</DataCollectorSet>
"@
            try {
                $pfComObject = New-Object -ComObject Pla.DataCollectorSet
                $pfComObject.SetXml($pfXml)
                $null = $pfComObject.Commit("dbatoolsci_PerfOutput", $null, 0x0003)
                $pfSetupSuccess = $true
            } catch {
                $pfSetupSuccess = $false
            }

            if ($pfSetupSuccess) {
                $outputResult = Start-DbaPfDataCollectorSet -CollectorSet "dbatoolsci_PerfOutput"
            }
        }

        AfterAll {
            $null = Stop-DbaPfDataCollectorSet -CollectorSet "dbatoolsci_PerfOutput" -ErrorAction SilentlyContinue
            try { $null = Remove-DbaPfDataCollectorSet -CollectorSet "dbatoolsci_PerfOutput" -ErrorAction SilentlyContinue } catch { }
        }

        It "Returns output with expected properties" {
            if (-not $pfSetupSuccess) { Set-ItResult -Skipped -Because "PerfMon collector set could not be created" }
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].ComputerName | Should -Be $env:COMPUTERNAME
            $outputResult[0].Name | Should -Not -BeNullOrEmpty
            $outputResult[0].State | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            if (-not $pfSetupSuccess -or -not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "Name", "DisplayName", "Description", "State", "Duration", "OutputLocation", "LatestOutputLocation", "RootPath", "SchedulesEnabled", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "StopOnCompletion", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskArguments", "TaskRunAsSelf", "TaskUserTextArguments", "UserAccount")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}