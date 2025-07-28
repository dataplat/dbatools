function Invoke-DbaPester {
    [CmdletBinding()]
    Param (
        [string[]]$Command,
        [string]$LocalConfigPath = "$PSScriptRoot\..\constants.local.ps1",
        [switch]$StopOnFailure
    )

    begin {
        Write-Verbose -Message "Importing dbatools"
        Import-Module -Name "$PSScriptRoot\..\..\dbatools.psm1" -Force -Verbose:$false
        if (Test-Path -Path $LocalConfigPath) {
            Write-Verbose -Message "Importing test configuration from $LocalConfigPath"
            $TestConfig = Get-TestConfig -LocalConfigPath $LocalConfigPath
        } else {
            Write-Verbose -Message "Importing test configuration"
            $TestConfig = Get-TestConfig
        }
        $testEnvironmentFilename = "$PSScriptRoot\TestEnvironment.Tests.ps1"
    }

    process {
        foreach ($cmd in $Command) {
            $files = Get-ChildItem -Path "$PSScriptRoot\.." -Filter "$cmd.Tests.ps1"
            foreach ($file in $files) {
                Write-Verbose -Message "Using [$($file.FullName)] for testing [$cmd]"

                $neededPesterVersion = if ((Get-Content -Path $file.FullName)[0] -match 'Requires.*Pester.*5') { 5 } else { 4 }
                $currentPesterVersion = (Get-Module -Name Pester).Version.Major
                if ($currentPesterVersion -ne $neededPesterVersion) {
                    Write-Verbose -Message "Changing pester version to $neededPesterVersion"
                    Remove-Module -Name Pester -ErrorAction SilentlyContinue -Verbose:$false
                    if ($neededPesterVersion -eq 5) {
                        Import-Module -Name Pester -MinimumVersion 5.0 -Verbose:$false
                    } else {
                        Import-Module -Name Pester -MaximumVersion 4.99 -Verbose:$false
                    }
                }

                Write-Verbose -Message "Starting test"
                if ($neededPesterVersion -eq 5) {
                    $resultTest = Invoke-Pester -Path $file.FullName -Output Detailed -PassThru
                    $resultEnvironment = Invoke-Pester -Path $testEnvironmentFilename -Output Minimal -PassThru
                    if ($resultTest.FailedCount -or $resultEnvironment.FailedCount) {
                        Write-Warning -Message "PLEASE REVIEW THIS TEST: $($file.FullName)"
                        if ($StopOnFailure) {
                            return
                        }
                    }
                } else {
                    $resultTest = Invoke-Pester -Script $file.FullName -Show All -PassThru
                    if ($resultTest.FailedCount -or $resultEnvironment.FailedCount) {
                        Write-Warning -Message "PLEASE REVIEW THIS TEST: $($file.FullName)"
                        if ($StopOnFailure) {
                            return
                        }
                    }
                }

            }
        }
    }
}