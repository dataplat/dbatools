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
    # AppVeyor is where they still fail: the command finds the error log through a SQL Server
    # startup event in the Windows Application log, and the CI runners have nothing to parse.

    BeforeDiscovery {
        # What actually failed, as that older note asked for: the command locates the error log by
        # reading event 17111 - the SQL Server startup event - from the Windows Application log,
        # and returns nothing at all when it is absent, because public\Get-DbaWindowsLog.ps1
        # returns early rather than warning. On the ephemeral ci-azure VMs that event is not
        # reliably there. It passed on one runner on 2026-08-06 and failed all three attempts on
        # another on 2026-08-07, returning empty in under a second each time.
        #
        # So the skip is back, but on the missing event rather than on $env:APPVEYOR. That old
        # condition described nothing after the move off AppVeyor: tests\gha.shim.ps1 still sets
        # the variable, so it skipped on every runner unconditionally.
        #
        # Reading the log here is not circular - it is the same precondition the command needs,
        # observed without going through the command. Where the event exists, the test runs.
        # Get-WinEvent throws when nothing matches, and the test session reads the log as the same
        # identity the command will, so a probe that cannot find the event means the command will
        # not find it either.
        $windowsLogComputer = "$($TestConfig.InstanceSingle)".Split("\")[0].Split(",")[0]
        $windowsLogInstance = "$($TestConfig.InstanceSingle)".Split("\")[1]
        if ($windowsLogComputer -in ".", "localhost", "(local)", "") {
            $windowsLogComputer = $env:COMPUTERNAME
        }
        if (-not $windowsLogInstance -or $windowsLogInstance -match "^DEFAULT$|^MSSQLSERVER$") {
            $windowsLogEventSource = "MSSQLSERVER"
        } else {
            $windowsLogEventSource = "MSSQL`$$windowsLogInstance"
        }

        try {
            $splatStartupEvent = @{
                FilterHashtable = @{
                    LogName      = "Application"
                    ID           = 17111
                    ProviderName = $windowsLogEventSource
                }
                MaxEvents       = 1
                ErrorAction     = "Stop"
            }
            if ($windowsLogComputer -ne $env:COMPUTERNAME) {
                $splatStartupEvent["ComputerName"] = $windowsLogComputer
            }
            $hasSqlStartupEvent = [bool](Get-WinEvent @splatStartupEvent)
        } catch {
            $hasSqlStartupEvent = $false
        }
    }

    Context "Command returns proper info" -Skip:(-not $hasSqlStartupEvent) {
        It "returns results" {
            $results = Get-DbaWindowsLog -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }
}