#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Scope",
                "Type",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing SqlPackage installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $results = Install-DbaSqlPackage -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # Clean up is not needed as SqlPackage installation is typically permanent
            # and safe to leave installed for other tests
        }

        It "Should have installed SqlPackage successfully" {
            $results.Installed | Should -Be $true
        }

        It "Returns an object with the expected properties" {
            $result = $results
            $ExpectedProps = 'Name', 'Path', 'Installed'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return a valid installation path" {
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -Be $true
        }

        It "Should be able to find SqlPackage after installation" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            $sqlPackagePath | Should -Not -BeNullOrEmpty
            Test-Path $sqlPackagePath | Should -Be $true
        }

        It "SqlPackage executable should be functional" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            if ($PSVersionTable.Platform -eq "Unix") {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP/sqlpackage_test.txt" -RedirectStandardError "$env:TEMP/sqlpackage_error.txt"
            } else {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\sqlpackage_test.txt" -RedirectStandardError "$env:TEMP\sqlpackage_error.txt"
            }
            $testProcess.ExitCode | Should -Be 0
            if ($PSVersionTable.Platform -eq "Unix") {
                Remove-Item "$env:TEMP/sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP/sqlpackage_error.txt" -ErrorAction SilentlyContinue
            } else {
                Remove-Item "$env:TEMP\sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP\sqlpackage_error.txt" -ErrorAction SilentlyContinue
            }
        }
    }

    # The elevation check only exists on Windows.
    Context "Stops without elevation instead of leaving the loop of the caller" -Skip:($PSVersionTable.Platform -eq "Unix") {
        BeforeAll {
            # The check needs a process that really runs without elevation. runas /trustlevel:0x20000 starts one for the same
            # user with a restricted token, without a prompt, and returns at once. The probe calls the command twice inside a
            # loop and records whether the code after each call still runs; a continue that leaves the command skips it.
            # No temp name starts with dbatools: the maintenance task tempcleanup may remove such items.
            $elevationProbePath = Join-Path ([System.IO.Path]::GetTempPath()) "sqlpackage_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $elevationProbePath -ItemType Directory
            $elevationProbeResult = Join-Path $elevationProbePath "result.txt"

            $elevationProbe = {
                param ($ModulePath, $InstallPath, $ResultFile)
                $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                $probeLines = @("elevated=$isElevated")
                try {
                    Import-Module $ModulePath -ErrorAction Stop
                    foreach ($round in 1, 2) {
                        $splatInstall = @{
                            Scope           = "AllUsers"
                            Type            = "Zip"
                            Path            = $InstallPath
                            Force           = $true
                            WarningVariable = "installWarning"
                            WarningAction   = "SilentlyContinue"
                        }
                        $null = Install-DbaSqlPackage @splatInstall
                        $probeLines += "after round $round"
                        $probeLines += "warning $installWarning"
                    }
                } catch {
                    $probeLines += "error $PSItem"
                }
                Set-Content -Path "$ResultFile.tmp" -Value $probeLines
                Move-Item -Path "$ResultFile.tmp" -Destination $ResultFile
            }

            $quote = [char]34
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "dbatools.psd1"
            $probeCommand = "& {$elevationProbe} -ModulePath $quote$modulePath$quote -InstallPath $quote$(Join-Path $elevationProbePath "install")$quote -ResultFile $quote$elevationProbeResult$quote"
            $encodedProbe = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($probeCommand))
            $probeHost = (Get-Process -Id $PID).Path
            $null = runas.exe /trustlevel:0x20000 "$probeHost -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encodedProbe"

            $probeWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path -Path $elevationProbeResult) -and $probeWatch.Elapsed.TotalMinutes -lt 3) {
                Start-Sleep -Seconds 1
            }
            $elevationProbeLines = @(Get-Content -Path $elevationProbeResult -ErrorAction SilentlyContinue)
        }

        AfterAll {
            Remove-Item -Path $elevationProbePath -Recurse -ErrorAction SilentlyContinue
        }

        It "Runs the probe in a process without elevation" {
            $elevationProbeLines | Should -Contain "elevated=False" -Because "the probe reported: $elevationProbeLines"
        }

        It "Returns to the caller, so the code after the call runs in every round" {
            $elevationProbeLines | Should -Contain "after round 1" -Because "the probe reported: $elevationProbeLines"
            $elevationProbeLines | Should -Contain "after round 2" -Because "the probe reported: $elevationProbeLines"
        }

        It "Warns that administrative privileges are needed" {
            $probeWarnings = @($elevationProbeLines | Where-Object { $PSItem -like "warning *" })
            $probeWarnings | Should -HaveCount 2 -Because "the probe reported: $elevationProbeLines"
            $probeWarnings | Where-Object { $PSItem -notmatch "require administrative privileges" } | Should -BeNullOrEmpty
        }

        It "Installs nothing" {
            Join-Path $elevationProbePath "install" | Should -Not -Exist
        }
    }
}
