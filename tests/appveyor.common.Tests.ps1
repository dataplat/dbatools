#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "appveyor.common",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        . "$PSScriptRoot\appveyor.common.ps1"
    }

    Context "Get-FunctionNameFromTestFile" {
        It "returns the command name for standard tests" {
            $testPath = Join-Path $PSScriptRoot "Get-DbaBuild.Tests.ps1"

            Get-FunctionNameFromTestFile $testPath | Should -Be "Get-DbaBuild"
        }

        It "returns the base command name for suffixed tests" {
            $testPath = Join-Path $PSScriptRoot "Get-DbaBuild.one.Tests.ps1"

            Get-FunctionNameFromTestFile $testPath | Should -Be "Get-DbaBuild"
        }
    }

    Context "Get-AllTestsIndications" {
        It "always includes the repository-wide general test file" {
            $moduleBase = Split-Path $PSScriptRoot -Parent
            $testPath = Join-Path $PSScriptRoot "Get-DbaBuild.Tests.ps1"

            $result = Get-AllTestsIndications -Path $testPath -ModuleBase $moduleBase

            $result.FullName | Should -Contain (Join-Path $PSScriptRoot "dbatools.Tests.ps1")
        }
    }

    Context "Write-TestHeartbeat" {
        BeforeAll {
            $heartbeatTempPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools-heartbeat-$(Get-Random)"
            $null = New-Item -Path $heartbeatTempPath -ItemType Directory
        }

        AfterAll {
            Remove-Item -Path $heartbeatTempPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "writes the tick count and the label" {
            $heartbeatFile = Join-Path $heartbeatTempPath "plain-$(Get-Random).txt"

            Write-TestHeartbeat -Path $heartbeatFile -Label "Get-DbaBuild.Tests.ps1"

            $heartbeatParts = (Get-Content -Path $heartbeatFile -TotalCount 1) -split "\|", 2
            $heartbeatParts[1] | Should -Be "Get-DbaBuild.Tests.ps1"
            [long]$writtenTicks = 0
            [System.Int64]::TryParse($heartbeatParts[0], [ref]$writtenTicks) | Should -BeTrue
            $writtenTicks | Should -BeGreaterThan 0
        }

        It "writes while the watchdog has the file open for reading" {
            # This is the regression. Set-Content refuses to share the file with a reader that
            # already has it open, and the watchdog reads this file every few seconds by design.
            # The collision surfaces as a terminating error that -ErrorAction SilentlyContinue
            # does not suppress, so one unlucky poll used to fail the entire test stage.
            $heartbeatFile = Join-Path $heartbeatTempPath "shared-$(Get-Random).txt"
            Write-TestHeartbeat -Path $heartbeatFile -Label "First.Tests.ps1"

            $watchdogShare = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $watchdogStream = [System.IO.File]::Open($heartbeatFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $watchdogShare)
            try {
                { Write-TestHeartbeat -Path $heartbeatFile -Label "Second.Tests.ps1" } | Should -Not -Throw

                # And the removal the runner does once the loop ends has to land too, otherwise
                # the watchdog keeps judging a stale heartbeat against the summary work
                Remove-Item -Path $heartbeatFile -Force -ErrorAction SilentlyContinue
                Test-Path -Path $heartbeatFile | Should -BeFalse
            } finally {
                $watchdogStream.Dispose()
            }
        }
    }
}
