#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWindowsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Start",
                "End",
                "Credential",
                "MaxThreads",
                "MaxRemoteThreads",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # These were skipped as "very unstable and should be reviewed". Reviewed on 2026-08-01: five
    # consecutive runs against the lab were all green, so they run again. If the instability comes
    # back, skip them once more but record what actually failed, not only that it is unstable.
    #
    # 2026-08-04, it came back (PR #10510): "returns results" got $null on a CI runner. The command
    # locates the ERRORLOG only through the newest service startup event 17111 in the Application
    # event log and silently returns nothing when that event is gone - a busy runner wraps the log
    # past the last SQL Server startup. That is machine state, not a command defect, so we probe
    # for the event the same way the command does and skip when it is provably missing.
    #
    # Later the same day the hardened test then WEDGED on the CI runner until the 15-minute
    # watchdog killed the whole run, so the file is excluded from CI via the appveyor_disabled
    # group in pester.groups.ps1. These tests remain for manual and lab runs.

    BeforeDiscovery {
        $instanceParam = [DbaInstanceParameter]$TestConfig.InstanceSingle
        $eventSource = "MSSQLSERVER"
        if ($instanceParam.InstanceName -notmatch "^DEFAULT$|^MSSQLSERVER$") {
            $eventSource = "MSSQL`$" + $instanceParam.InstanceName
        }
        $probeScript = {
            param($Source)
            $filterStartupEvent = @{
                LogName      = "Application"
                ID           = 17111
                ProviderName = $Source
            }
            $splatStartupEvent = @{
                FilterHashtable = $filterStartupEvent
                MaxEvents       = 1
                ErrorAction     = "Stop"
            }
            Get-WinEvent @splatStartupEvent
        }
        $splatProbe = @{
            ScriptBlock  = $probeScript
            ArgumentList = $eventSource
            ErrorAction  = "Stop"
        }
        if (-not $instanceParam.IsLocalhost) { $splatProbe["ComputerName"] = $instanceParam.ComputerName }
        try {
            $startupEventFound = [bool](Invoke-Command @splatProbe)
        } catch {
            # NoMatchingEventsFound is the one state we skip for: the provider resolves but the
            # startup event has aged out of the Application log, so the command cannot locate
            # the ERRORLOG on an otherwise healthy host (the FullyQualifiedErrorId survives the
            # remoting boundary). Anything else - an unresolvable provider name, broken
            # remoting, permissions, an unset TestConfig - must fail discovery loudly instead
            # of green-skipping the whole context.
            if ($PSItem.FullyQualifiedErrorId -like "NoMatchingEventsFound*") {
                $startupEventFound = $false
            } else {
                throw
            }
        }
    }

    Context "Command returns proper info" -Skip:(-not $startupEventFound) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command only emits ERRORLOG lines that match the "Error: n, Severity: n, State: n"
            # pattern, and service restarts from earlier tests can cycle every retained ERRORLOG so
            # that no such line survives. xp_logevent writes exactly that header without raising a
            # client-side error, so the current log always holds one parseable entry.
            $queryLogEvent = @"
EXEC master.dbo.xp_logevent 50001, 'dbatools Get-DbaWindowsLog integration test marker', ERROR
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $queryLogEvent

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns results" {
            $results = Get-DbaWindowsLog -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
