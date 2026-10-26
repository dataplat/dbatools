#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "appveyor.watchdog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    # The watchdog drives real processes, so these tests need a powershell.exe to sacrifice.
    # $IsWindows does not exist on 5.1, where it evaluates to $null and would skip the whole
    # block on the very platform this runs on, so the platform is read a way that is correct
    # on both editions.
    $onWindows = $PSVersionTable.Platform -ne "Unix"

    Context "Watching a wedged run" -Skip:(-not $onWindows) {
        BeforeAll {
            $watchdogScript = Join-Path $PSScriptRoot "appveyor.watchdog.ps1"
            $watchdogTempPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools-watchdog-$(Get-Random)"
            $null = New-Item -Path $watchdogTempPath -ItemType Directory

            # A sleeper stands in for a wedged test process. Both variants live in script files so
            # nothing has to survive a round trip through nested command line quoting.
            $sleeperScript = Join-Path $watchdogTempPath "sleeper.ps1"
            Set-Content -Path $sleeperScript -Value "Start-Sleep -Seconds 600"

            $sleeperWithChildScript = Join-Path $watchdogTempPath "sleeper-with-child.ps1"
            $childLauncher = "Start-Process powershell.exe -ArgumentList `"-NoProfile`", `"-File`", `"$sleeperScript`" -WindowStyle Hidden"
            Set-Content -Path $sleeperWithChildScript -Value @($childLauncher, "Start-Sleep -Seconds 600")

            # Everything this suite starts is tracked so a failed assertion cannot leak a runaway
            # process onto the build agent
            $script:startedProcessIds = @()

            function New-SacrificialProcess {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
                param(
                    [switch]$WithChild
                )

                if ($WithChild) {
                    $sacrificeScript = $sleeperWithChildScript
                } else {
                    $sacrificeScript = $sleeperScript
                }

                $splatSacrifice = @{
                    FilePath     = "powershell.exe"
                    ArgumentList = @("-NoProfile", "-NonInteractive", "-File", "`"$sacrificeScript`"")
                    PassThru     = $true
                    WindowStyle  = "Hidden"
                }
                $sacrifice = Start-Process @splatSacrifice
                $script:startedProcessIds += $sacrifice.Id
                return $sacrifice
            }

            function Start-TestWatchdog {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
                param(
                    [int]$TargetProcessId,
                    [string]$HeartbeatFile,
                    [int]$TimeoutMinutes = 1,
                    [int]$PollSeconds = 1
                )

                $splatWatchdogRun = @{
                    FilePath     = "powershell.exe"
                    ArgumentList = @(
                        "-NoProfile"
                        "-NonInteractive"
                        "-ExecutionPolicy", "Bypass"
                        "-File", "`"$watchdogScript`""
                        "-ParentProcessId", $TargetProcessId
                        "-HeartbeatPath", "`"$HeartbeatFile`""
                        "-TimeoutMinutes", $TimeoutMinutes
                        "-PollSeconds", $PollSeconds
                    )
                    PassThru     = $true
                    WindowStyle  = "Hidden"
                }
                $watchdog = Start-Process @splatWatchdogRun
                $script:startedProcessIds += $watchdog.Id
                return $watchdog
            }

            function Test-ProcessRunning {
                param(
                    [int]$ProcessId
                )

                return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
            }

            function Wait-ForProcessExit {
                param(
                    [int]$ProcessId,
                    [int]$TimeoutSeconds = 30
                )

                $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                while ((Get-Date) -lt $deadline) {
                    if (-not (Test-ProcessRunning -ProcessId $ProcessId)) {
                        return $true
                    }
                    Start-Sleep -Milliseconds 250
                }
                return $false
            }

            function New-HeartbeatFile {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
                param(
                    [int]$AgeMinutes,
                    [string]$Label = "Wedged.Tests.ps1"
                )

                $heartbeatFile = Join-Path $watchdogTempPath "heartbeat-$(Get-Random).txt"
                $heartbeatTicks = ((Get-Date).AddMinutes(-$AgeMinutes)).Ticks
                Set-Content -Path $heartbeatFile -Value "$heartbeatTicks|$Label"
                return $heartbeatFile
            }
        }

        AfterAll {
            foreach ($startedProcessId in $script:startedProcessIds) {
                $splatCleanup = @{
                    Id          = $startedProcessId
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Stop-Process @splatCleanup
            }
            Remove-Item -Path $watchdogTempPath -Recurse -ErrorAction SilentlyContinue
        }

        It "kills the watched process when a heartbeat goes stale" {
            $sacrifice = New-SacrificialProcess
            $heartbeatFile = New-HeartbeatFile -AgeMinutes 60

            $null = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile

            Wait-ForProcessExit -ProcessId $sacrifice.Id | Should -BeTrue
        }

        It "kills the processes the watched run left behind" {
            $sacrifice = New-SacrificialProcess -WithChild
            Start-Sleep -Seconds 3
            $childIds = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($sacrifice.Id)" | Where-Object Name -eq "powershell.exe" | Select-Object -ExpandProperty ProcessId)
            $childIds.Count | Should -BeGreaterThan 0
            $script:startedProcessIds += $childIds

            $heartbeatFile = New-HeartbeatFile -AgeMinutes 60
            $null = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile

            Wait-ForProcessExit -ProcessId $sacrifice.Id | Should -BeTrue
            Wait-ForProcessExit -ProcessId $childIds[0] | Should -BeTrue
        }

        It "leaves the watched process alone while the heartbeat is fresh" {
            $sacrifice = New-SacrificialProcess
            $heartbeatFile = New-HeartbeatFile -AgeMinutes 0

            $null = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile
            Start-Sleep -Seconds 8

            Test-ProcessRunning -ProcessId $sacrifice.Id | Should -BeTrue
        }

        It "leaves the watched process alone when there is no heartbeat at all" {
            $sacrifice = New-SacrificialProcess
            $missingHeartbeat = Join-Path $watchdogTempPath "absent-$(Get-Random).txt"

            $null = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $missingHeartbeat
            Start-Sleep -Seconds 8

            Test-ProcessRunning -ProcessId $sacrifice.Id | Should -BeTrue
        }

        It "stops itself once the watched process is gone" {
            $sacrifice = New-SacrificialProcess
            $heartbeatFile = New-HeartbeatFile -AgeMinutes 0

            $watchdog = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile
            Stop-Process -Id $sacrifice.Id -Force

            Wait-ForProcessExit -ProcessId $watchdog.Id | Should -BeTrue
        }

        It "refuses to watch a process that is not running, so a reused PID is never killed" {
            $sacrifice = New-SacrificialProcess
            $deadProcessId = $sacrifice.Id
            Stop-Process -Id $deadProcessId -Force
            $null = Wait-ForProcessExit -ProcessId $deadProcessId

            $heartbeatFile = New-HeartbeatFile -AgeMinutes 60
            $watchdog = Start-TestWatchdog -TargetProcessId $deadProcessId -HeartbeatFile $heartbeatFile

            Wait-ForProcessExit -ProcessId $watchdog.Id -TimeoutSeconds 20 | Should -BeTrue
        }

        It "still reads a heartbeat the runner is holding open" {
            # The runner keeps a write handle on this file while it records the next test, so a
            # watchdog that asked for exclusive access would go blind exactly when a run is
            # active and would never notice the wedge it exists to catch
            $sacrifice = New-SacrificialProcess
            $heartbeatFile = New-HeartbeatFile -AgeMinutes 60

            $heldStream = [System.IO.File]::Open($heartbeatFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try {
                $null = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile
                Wait-ForProcessExit -ProcessId $sacrifice.Id | Should -BeTrue
            } finally {
                $heldStream.Dispose()
            }
        }

        It "rejects a timeout outside the supported range" {
            $sacrifice = New-SacrificialProcess
            $heartbeatFile = New-HeartbeatFile -AgeMinutes 0

            $watchdog = Start-TestWatchdog -TargetProcessId $sacrifice.Id -HeartbeatFile $heartbeatFile -TimeoutMinutes 0

            $watchdog.WaitForExit(20000) | Should -BeTrue
            $watchdog.ExitCode | Should -Not -Be 0
        }
    }
}
