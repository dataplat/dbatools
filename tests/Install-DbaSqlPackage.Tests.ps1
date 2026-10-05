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
            # The check needs a process that really runs without elevation. A scheduled task starts one as LOCAL SERVICE, a
            # built-in account without administrative privileges and without a password. runas /trustlevel:0x20000 does not
            # work here: the CI runner is LocalSystem, and its restricted token still holds the Administrators group.
            # The probe calls the command twice inside a loop and records whether the code after each call still runs;
            # a continue that leaves the command skips it.
            # The probe folder is not in the temp folder: LOCAL SERVICE cannot write to the one of LocalSystem.
            # No temp name starts with dbatools: the maintenance task tempcleanup may remove such items.
            $probeAccount = (New-Object System.Security.Principal.SecurityIdentifier "S-1-5-19").Translate([System.Security.Principal.NTAccount]).Value
            $elevationProbePath = Join-Path $env:ProgramData "sqlpackage_dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $elevationProbePath -ItemType Directory
            $probeAcl = Get-Acl -Path $elevationProbePath
            $probeAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($probeAccount, "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")))
            Set-Acl -Path $elevationProbePath -AclObject $probeAcl
            $elevationProbeResult = Join-Path $elevationProbePath "result.txt"
            $probeTaskName = "sqlpackage_dbatoolsci_$(Get-Random)"

            $elevationProbe = {
                param ($ModulePath, $InstallPath, $ResultFile)
                $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                $probeLines = @("elevated=$isElevated")
                try {
                    $importWatch = [System.Diagnostics.Stopwatch]::StartNew()
                    Import-Module $ModulePath -ErrorAction Stop
                    $probeLines += "import seconds=$([int]$importWatch.Elapsed.TotalSeconds)"
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
                        # One line per warning: a missing SqlPackage adds a warning that spans several lines.
                        foreach ($warningRecord in $installWarning) {
                            $probeLines += "warning $round $("$warningRecord" -replace "\s+", " ")"
                        }
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
            $probeAction = New-ScheduledTaskAction -Execute $probeHost -Argument "-NoProfile -NonInteractive -EncodedCommand $encodedProbe"
            $probePrincipal = New-ScheduledTaskPrincipal -UserId $probeAccount -LogonType ServiceAccount
            $splatProbeSettings = @{
                AllowStartIfOnBatteries    = $true
                DontStopIfGoingOnBatteries = $true
                ExecutionTimeLimit         = New-TimeSpan -Minutes 15
            }
            $probeSettings = New-ScheduledTaskSettingsSet @splatProbeSettings
            $splatProbeTask = @{
                TaskName  = $probeTaskName
                Action    = $probeAction
                Principal = $probePrincipal
                Settings  = $probeSettings
            }
            $null = Register-ScheduledTask @splatProbeTask
            Start-ScheduledTask -TaskName $probeTaskName

            $probeWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path -Path $elevationProbeResult) -and $probeWatch.Elapsed.TotalMinutes -lt 10) {
                Start-Sleep -Seconds 1
            }
            $elevationProbeLines = @(Get-Content -Path $elevationProbeResult -ErrorAction SilentlyContinue)
            $elevationProbeLines += "waited seconds=$([int]$probeWatch.Elapsed.TotalSeconds)"
        }

        AfterAll {
            # Unregistering a task does not end its process, so stop it first.
            Stop-ScheduledTask -TaskName $probeTaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $probeTaskName -Confirm:$false -ErrorAction SilentlyContinue
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
            # Without SqlPackage, Get-DbaSqlPackagePath warns first that it is missing; only the elevation warning counts here.
            foreach ($round in 1, 2) {
                $elevationWarnings = @($elevationProbeLines | Where-Object { $PSItem -like "warning $round *" -and $PSItem -match "require administrative privileges" })
                $elevationWarnings | Should -HaveCount 1 -Because "round $round should warn once; the probe reported: $elevationProbeLines"
            }
        }

        It "Installs nothing" {
            Join-Path $elevationProbePath "install" | Should -Not -Exist
        }
    }
}
