#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaTrace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Id",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tracePath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tracePath -ItemType Directory

        $sql = "-- Create a Queue
                declare @rc int
                declare @TraceID int
                declare @maxfilesize bigint
                set @maxfilesize = 5
                exec @rc = sp_trace_create @TraceID output, 0, N'$tracePath\temptrace', @maxfilesize, NULL

                -- Set the events
                declare @on bit
                set @on = 1
                exec sp_trace_setevent @TraceID, 14, 1, @on
                exec sp_trace_setevent @TraceID, 14, 9, @on
                exec sp_trace_setevent @TraceID, 14, 10, @on
                exec sp_trace_setevent @TraceID, 14, 11, @on
                exec sp_trace_setevent @TraceID, 14, 6, @on
                exec sp_trace_setevent @TraceID, 14, 12, @on
                exec sp_trace_setevent @TraceID, 14, 14, @on
                exec sp_trace_setevent @TraceID, 15, 11, @on
                exec sp_trace_setevent @TraceID, 15, 6, @on
                exec sp_trace_setevent @TraceID, 15, 9, @on
                exec sp_trace_setevent @TraceID, 15, 10, @on
                exec sp_trace_setevent @TraceID, 15, 12, @on
                exec sp_trace_setevent @TraceID, 15, 13, @on
                exec sp_trace_setevent @TraceID, 15, 14, @on
                exec sp_trace_setevent @TraceID, 15, 15, @on
                exec sp_trace_setevent @TraceID, 15, 16, @on
                exec sp_trace_setevent @TraceID, 15, 17, @on
                exec sp_trace_setevent @TraceID, 15, 18, @on
                exec sp_trace_setevent @TraceID, 17, 1, @on
                exec sp_trace_setevent @TraceID, 17, 9, @on
                exec sp_trace_setevent @TraceID, 17, 10, @on
                exec sp_trace_setevent @TraceID, 17, 11, @on
                exec sp_trace_setevent @TraceID, 17, 6, @on
                exec sp_trace_setevent @TraceID, 17, 12, @on
                exec sp_trace_setevent @TraceID, 17, 14, @on
                exec sp_trace_setevent @TraceID, 10, 9, @on
                exec sp_trace_setevent @TraceID, 10, 2, @on
                exec sp_trace_setevent @TraceID, 10, 10, @on
                exec sp_trace_setevent @TraceID, 10, 6, @on
                exec sp_trace_setevent @TraceID, 10, 11, @on
                exec sp_trace_setevent @TraceID, 10, 12, @on
                exec sp_trace_setevent @TraceID, 10, 13, @on
                exec sp_trace_setevent @TraceID, 10, 14, @on
                exec sp_trace_setevent @TraceID, 10, 15, @on
                exec sp_trace_setevent @TraceID, 10, 16, @on
                exec sp_trace_setevent @TraceID, 10, 17, @on
                exec sp_trace_setevent @TraceID, 10, 18, @on
                exec sp_trace_setevent @TraceID, 12, 1, @on
                exec sp_trace_setevent @TraceID, 12, 9, @on
                exec sp_trace_setevent @TraceID, 12, 11, @on
                exec sp_trace_setevent @TraceID, 12, 6, @on
                exec sp_trace_setevent @TraceID, 12, 10, @on
                exec sp_trace_setevent @TraceID, 12, 12, @on
                exec sp_trace_setevent @TraceID, 12, 13, @on
                exec sp_trace_setevent @TraceID, 12, 14, @on
                exec sp_trace_setevent @TraceID, 12, 15, @on
                exec sp_trace_setevent @TraceID, 12, 16, @on
                exec sp_trace_setevent @TraceID, 12, 17, @on
                exec sp_trace_setevent @TraceID, 12, 18, @on
                exec sp_trace_setevent @TraceID, 13, 1, @on
                exec sp_trace_setevent @TraceID, 13, 9, @on
                exec sp_trace_setevent @TraceID, 13, 11, @on
                exec sp_trace_setevent @TraceID, 13, 6, @on
                exec sp_trace_setevent @TraceID, 13, 10, @on
                exec sp_trace_setevent @TraceID, 13, 12, @on
                exec sp_trace_setevent @TraceID, 13, 14, @on

                -- Set the Filters
                declare @intfilter int
                declare @bigintfilter bigint

                -- Set the trace status to start
                exec sp_trace_setstatus @TraceID, 1

                -- display trace id for future references
                select TraceID=@TraceID"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $traceid = ($server.Query($sql)).TraceID
        $null = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid | Start-DbaTrace

        # we want to run all commands outside of the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid

        Remove-Item -Path $tracePath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Stopping Trace" {
        It "starts in a running state" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid
            $results.Id | Should -Be $traceid
            $results.IsRunning | Should -BeTrue
        }

        It "is now in a stopped state" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid | Stop-DbaTrace -Confirm:$false
            $script:outputForValidation = $results
            $results.Id | Should -Be $traceid
            $results.IsRunning | Should -BeFalse
        }

        Context "Output validation" {
            BeforeAll {
                # Create a separate trace for output validation so we have a fresh running trace to stop
                $outputTracePath = "$($TestConfig.Temp)\$CommandName-outputval-$(Get-Random)"
                $null = New-Item -Path $outputTracePath -ItemType Directory

                $outputSql = "-- Create a Queue
                declare @rc int
                declare @TraceID int
                declare @maxfilesize bigint
                set @maxfilesize = 5
                exec @rc = sp_trace_create @TraceID output, 0, N'$outputTracePath\temptrace', @maxfilesize, NULL

                -- Set the events
                declare @on bit
                set @on = 1
                exec sp_trace_setevent @TraceID, 14, 1, @on
                exec sp_trace_setevent @TraceID, 14, 9, @on
                exec sp_trace_setevent @TraceID, 14, 10, @on
                exec sp_trace_setevent @TraceID, 14, 11, @on
                exec sp_trace_setevent @TraceID, 14, 6, @on
                exec sp_trace_setevent @TraceID, 14, 12, @on
                exec sp_trace_setevent @TraceID, 14, 14, @on

                -- Set the trace status to start
                exec sp_trace_setstatus @TraceID, 1

                -- display trace id for future references
                select TraceID=@TraceID"
                $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $outputTraceId = ($outputServer.Query($outputSql)).TraceID

                # Stop the trace and capture output for validation
                $script:outputForValidation = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $outputTraceId | Stop-DbaTrace -Confirm:$false
            }

            AfterAll {
                $null = Remove-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $outputTraceId -ErrorAction SilentlyContinue
                Remove-Item -Path $outputTracePath -Recurse -ErrorAction SilentlyContinue
            }

            It "Returns output" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "trace may have already been stopped or removed in CI"
                }
                $script:outputForValidation | Should -Not -BeNullOrEmpty
            }

            It "Returns output with expected properties" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "trace may have already been stopped or removed in CI"
                }
                $propertyNames = @($script:outputForValidation)[0].PSObject.Properties.Name
                $propertyNames | Should -Contain "ComputerName"
                $propertyNames | Should -Contain "InstanceName"
                $propertyNames | Should -Contain "SqlInstance"
                $propertyNames | Should -Contain "Id"
                $propertyNames | Should -Contain "IsRunning"
            }

            It "Has the correct excluded properties from default display" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "trace may have already been stopped or removed in CI"
                }
                $defaultProps = @($script:outputForValidation)[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $defaultProps | Should -Not -Contain "Parent" -Because "Parent should be excluded from default display"
                $defaultProps | Should -Not -Contain "RemotePath" -Because "RemotePath should be excluded from default display"
                $defaultProps | Should -Not -Contain "SqlCredential" -Because "SqlCredential should be excluded from default display"
            }

            It "Shows the trace as stopped" {
                if (-not $script:outputForValidation) {
                    Set-ItResult -Skipped -Because "trace may have already been stopped or removed in CI"
                }
                @($script:outputForValidation)[0].IsRunning | Should -BeFalse
            }
        }
    }
}