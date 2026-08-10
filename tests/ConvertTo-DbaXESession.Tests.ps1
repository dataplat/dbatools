#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "ConvertTo-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "Name",
                "SqlCredential",
                "OutputScriptOnly",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tracePath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tracePath -ItemType Directory

        $sql = @"
-- Create a Queue
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

exec sp_trace_setfilter @TraceID, 10, 0, 7, N'SQL Server Profiler - 934a8575-0dc1-4937-bde1-edac1cb9691f'
-- Set the trace status to start
exec sp_trace_setstatus @TraceID, 1

-- display trace id for future references
select TraceID=@TraceID
"@
        $splatConnect = @{
            SqlInstance = $TestConfig.InstanceSingle
        }
        $server = Connect-DbaInstance @splatConnect
        $traceid = ($server.Query($sql)).TraceID
        $traceidSecond = ($server.Query($sql.Replace("temptrace", "temptrace-second"))).TraceID
        $sessionName = "dbatoolsci-session-$(Get-Random)"
        $carrierSessionName = "dbatoolsci-carrier-$(Get-Random)"
        $null = $server.Query("CREATE EVENT SESSION [$carrierSessionName] ON SERVER ADD EVENT sqlserver.sql_statement_completed;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveSession = @{
            SqlInstance = $TestConfig.InstanceSingle
            Session     = $sessionName
        }
        $null = Remove-DbaXESession @splatRemoveSession
        $splatRemoveCarrierSession = @{
            SqlInstance = $TestConfig.InstanceSingle
            Session     = $carrierSessionName
        }
        $null = Remove-DbaXESession @splatRemoveCarrierSession
        $splatRemoveTrace = @{
            SqlInstance = $TestConfig.InstanceSingle
            Id          = $traceid
        }
        $null = Remove-DbaTrace @splatRemoveTrace
        $splatRemoveSecondTrace = @{
            SqlInstance = $TestConfig.InstanceSingle
            Id          = $traceidSecond
        }
        $null = Remove-DbaTrace @splatRemoveSecondTrace
        Remove-Item -Path $tracePath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Trace Conversion" {
        BeforeAll {
            $splatGetTrace = @{
                SqlInstance = $TestConfig.InstanceSingle
                Id          = $traceid
            }
            $null = Get-DbaTrace @splatGetTrace | ConvertTo-DbaXESession -Name $sessionName
            $splatStartSession = @{
                SqlInstance = $TestConfig.InstanceSingle
                Session     = $sessionName
            }
            $results = Start-DbaXESession @splatStartSession
        }

        It "Returns the right results" {
            $results.Name | Should -Be $sessionName
            $results.Status | Should -Be "Running"
            $results.Targets.Name | Should -Be "package0.event_file"
        }

        It "Carries conflict-renamed Name across two piped trace records" {
            $traces = @(
                Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid
                Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceidSecond
            )
            $scripts = @($traces | ConvertTo-DbaXESession -Name $carrierSessionName -OutputScriptOnly -EnableException)
            $expectedFirst = "$carrierSessionName-$traceid"
            $expectedSecond = "$expectedFirst-$traceidSecond"

            $scripts | Should -HaveCount 2
            $scripts[0] | Should -Match [regex]::Escape($expectedFirst)
            $scripts[1] | Should -Match [regex]::Escape($expectedSecond)
        }

        It "Resets the mutable Name between separate invocations" {
            $firstScript = @(ConvertTo-DbaXESession -InputObject (Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid) -Name $carrierSessionName -OutputScriptOnly -EnableException)
            $secondScript = @(ConvertTo-DbaXESession -InputObject (Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceidSecond) -Name $carrierSessionName -OutputScriptOnly -EnableException)
            $expectedFirst = "$carrierSessionName-$traceid"
            $expectedSecond = "$carrierSessionName-$traceidSecond"
            $carriedSecond = "$expectedFirst-$traceidSecond"

            $firstScript | Should -HaveCount 1
            $firstScript[0] | Should -Match [regex]::Escape($expectedFirst)
            $secondScript | Should -HaveCount 1
            $secondScript[0] | Should -Match [regex]::Escape($expectedSecond)
            $secondScript[0] | Should -Not -Match [regex]::Escape($carriedSecond)
        }

        It "Streams an earlier array element before a later element terminates" {
            $trace = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle -Id $traceid
            $unsupportedTrace = [pscustomobject]@{
                Id     = 900001
                Parent = [pscustomobject]@{
                    VersionMajor = 10
                    Name         = "unsupported-$([guid]::NewGuid().ToString('N'))"
                }
            }
            $streamed = [System.Collections.ArrayList]::new()
            $caught = $null

            try {
                ConvertTo-DbaXESession -InputObject @($trace, $unsupportedTrace) -Name $carrierSessionName -OutputScriptOnly -EnableException |
                    ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $caught = $PSItem
            }

            $streamed | Should -HaveCount 1
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -Match "2012"
        }
    }
}
