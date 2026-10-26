function Invoke-ManualPester {
<#
.SYNOPSIS
    Runs dbatools tests locally the way the CI runs them.

.DESCRIPTION
    This is a helper function to automate running tests locally. It imports the module from the
    working copy, runs the given test files with Pester, and reports at the end which files failed
    and why, so that a run over several files does not have to be read by scrolling back.

    It also runs the style checks that CI enforces but that live outside the per-command test files
    and are therefore easy to miss locally:

    - ScriptAnalyzer checks the test file and the command under test, using the dbatools profile.
    - Compliance runs the repository wide checks from tests\dbatools.Tests.ps1 (no UTF-8 BOM,
      no tabs, no trailing spaces, no ScriptAnalyzer errors).

.PARAMETER Path
    The Path to the test files to run. It accepts multiple test file paths passed in (e.g. .\Find-DbaOrphanedFile.Tests.ps1) as well
    as simple strings (e.g. "orphaned" will run all files matching .\*orphaned*.Tests.ps1)

.PARAMETER Show
    Gets passed down to Pester's Output.Verbosity setting (useful if you want to reduce verbosity)
    Valid values are: None, Normal, Detailed, Diagnostic

.PARAMETER PassThru
    Gets passed down to Pester's PassThru setting (useful if you want to return an object to analyze)

.PARAMETER TestIntegration
    dbatools's suite has unittests and integrationtests. This switch enables IntegrationTests, which need live instances
    see Get-TestConfig for customizations

.PARAMETER Coverage
    Enables measuring code coverage on the tested function, in JaCoCo format.

.PARAMETER DependencyCoverage
    Enables measuring code coverage also of "lower level" (i.e. called) functions

.PARAMETER ScriptAnalyzer
    Enables checking the test file and the command under test with Invoke-ScriptAnalyzer, using
    dbatools's profile in tests\PSScriptAnalyzerRules.psd1. Combined with DependencyCoverage the
    called functions are checked as well.

.PARAMETER Compliance
    Runs the Compliance tagged tests from tests\dbatools.Tests.ps1 before the test files.

    These are the repository wide checks that CI runs in its "default" lane: no UTF-8 BOM, no tabs,
    no trailing spaces and no ScriptAnalyzer errors, across every PowerShell file in the repository.
    They belong to no single command, so a green run of a command's own test file says nothing about
    them and a pull request can still fail CI on style. They take about half a minute.

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage -DependencyCoverage -ScriptAnalyzer -Compliance

    The most complete number of checks:
    - Runs the repository wide compliance checks
    - Runs both unittests and integrationtests
    - Gathers and shows code coverage measurement for Find-DbaOrphanedFile and all its dependencies
    - Checks the test file, Find-DbaOrphanedFile and its dependencies with Invoke-ScriptAnalyzer

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -PassThru

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1 and returns an object that can be analyzed

.EXAMPLE
    Invoke-ManualPester -Path orphan

    Runs tests for all tests matching in `*orphan*.Tests.ps1

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -Show Normal

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1, with reduced verbosity

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration

    Runs both unittests and integrationtests stored in Find-DbaOrphanedFile.Tests.ps1

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -ScriptAnalyzer -Compliance

    Runs the tests and then the two style checks that CI enforces but that a per-command test run
    does not cover. This is the combination to use before opening a pull request.

.NOTES
    Every test file has to carry this requirement in its first line:
    #Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }

    A file without it is reported and skipped rather than run, because a missing header is a
    mistake in the test file and not a request for a different runtime.
#>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [ValidateSet("None", "Normal", "Detailed", "Diagnostic")]
        [string]$Show = "Normal",
        [switch]$PassThru,
        [switch]$TestIntegration,
        [switch]$Coverage,
        [switch]$DependencyCoverage,
        [switch]$ScriptAnalyzer,
        [switch]$Compliance
    )
    begin {
        Remove-Module -Name Pester -ErrorAction SilentlyContinue
        $stopProcess = $false
        function Get-CoverageIndications($Path, $ModuleBase) {
            # takes a test file path and figures out what to analyze for coverage (i.e. dependencies)
            $CBHRex = [regex]"(?smi)<#(.*)#>"
            $everything = (Get-Module dbatools).ExportedCommands.Values
            $everyfunction = $everything.Name
            $funcs = @()
            $leaf = Split-Path $path -Leaf
            # assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
            # but allowing also Get-DbaFoo.one.Tests.ps1 and Get-DbaFoo.two.Tests.ps1
            $func_name += ($leaf -replace "^([^.]+)(.+)?.Tests.ps1", "`$1")
            if ($func_name -in $everyfunction) {
                $funcs += $func_name
                $f = $everything | Where-Object Name -eq $func_name
                $source = $f.Definition
                $CBH = $CBHRex.match($source).Value
                $cmdonly = $source.Replace($CBH, "")
                foreach ($e in $everyfunction) {
                    # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
                    $searchme = "$e "
                    if ($cmdonly.contains($searchme)) {
                        $funcs += $e
                    }
                }
            }
            $testpaths = @()
            $allfiles = Get-ChildItem -File -Path "$ModuleBase\private\functions", "$ModuleBase\public" -Filter "*.ps1"
            foreach ($f in $funcs) {
                # exclude always used functions ?!
                if ($f -in ("Connect-DbaInstance", "Select-DefaultView", "Stop-Function", "Write-Message")) { continue }
                # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
                $res = $allfiles | Where-Object { $PSItem.Name.Replace(".ps1", "") -eq $f }
                if ($res.count -gt 0) {
                    $testpaths += $res.FullName
                }
            }
            return @() + ($testpaths | Select-Object -Unique)
        }

        # The file that defines the command a test file belongs to, or nothing for the few test
        # files that do not test a single command (dbatools.Tests.ps1, InModule.*, appveyor.*).
        # Get-CoverageIndications cannot answer this: it returns the command and its dependencies
        # in one list, and for a command it does not know - a private function, or one that is not
        # exported yet - it returns nothing at all while its dependencies are still found. Taking
        # the first entry of that list therefore silently analysed and measured a dependency
        # instead of the command under test.
        function Get-CommandFile($testFilePath, $ModuleBase) {
            # Get-DbaFoo.Tests.ps1, and also Get-DbaFoo.one.Tests.ps1, belong to Get-DbaFoo
            $commandName = (Split-Path $testFilePath -Leaf) -replace "^([^.]+)(.+)?.Tests.ps1", "`$1"
            $splatCommandFile = @{
                Path        = "$ModuleBase\public", "$ModuleBase\private"
                Filter      = "$commandName.ps1"
                File        = $true
                Recurse     = $true
                ErrorAction = "SilentlyContinue"
            }
            return (Get-ChildItem @splatCommandFile | Select-Object -First 1).FullName
        }

        # Every test file has to declare the minimum Pester version it needs. A file without the
        # header is a mistake in the file and not a request for a different runtime - it is
        # reported instead of being run with something else.
        function Test-PesterTestHeader($testFilePath) {
            $testFileContent = Get-Content -Path $testFilePath -Raw
            return $testFileContent -match "#Requires\s+-Module\s+@\{\s+ModuleName=`"Pester`";\s+ModuleVersion=`"5\."
        }

        # Go up the folder structure until we find the root of the module, where dbatools.psd1 is located
        function Get-ModuleBase {
            $startOfSearch = $PSScriptRoot
            for ($i = 0; $i -lt 10; $i++) {
                if (Test-Path (Join-Path $startOfSearch "dbatools.psd1")) {
                    return $startOfSearch
                }
                $startOfSearch = Split-Path -Path $startOfSearch -Parent
            }
        }

        function Write-DetailedMessage($message) {
            if ($Show -in @("Normal", "Detailed", "Diagnostic")) {
                Write-Host -Object $message
            }
        }

        $invokeFormatterVersion = (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
        $HasScriptAnalyzer = $null -ne $invokeFormatterVersion
        # The suite runs on Pester 6, which the CI pins to 6.0.0 in tests\appveyor.prep.ps1. A local
        # run is gated to the same major version so a local pass means the same thing CI does.
        # Three components, not four: Pester reports itself as 6.0.0, and [Version] treats an absent
        # revision as -1, so "6.0.0" would compare as lower than "6.0.0.0" and reject the pinned build.
        $MinimumPesterVersion = [Version] "6.0.0"
        $MaximumPesterVersion = [Version] "7.0.0"
        $PesterVersion = (Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version
        $HasPester = $null -ne $PesterVersion
        $ScriptAnalyzerCorrectVersion = "1.18.2"

        if (!($HasScriptAnalyzer)) {
            Write-Warning "Please install PSScriptAnalyzer"
            Write-Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion $ScriptAnalyzerCorrectVersion"
            Write-Warning "     or go to https://github.com/PowerShell/PSScriptAnalyzer"
        } else {
            if ($invokeFormatterVersion -ne $ScriptAnalyzerCorrectVersion) {
                Remove-Module PSScriptAnalyzer -ErrorAction SilentlyContinue
                try {
                    Import-Module PSScriptAnalyzer -RequiredVersion $ScriptAnalyzerCorrectVersion -ErrorAction Stop
                } catch {
                    Write-Warning "Please install PSScriptAnalyzer $ScriptAnalyzerCorrectVersion"
                    Write-Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion $ScriptAnalyzerCorrectVersion"
                }
                # Re-read the version after the corrective import so the gate below compares the
                # module that is loaded now, not the stale value captured before Import-Module ran
                $invokeFormatterVersion = (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
                $HasScriptAnalyzer = $null -ne $invokeFormatterVersion
            }
        }

        if (!($HasPester)) {
            Write-Warning "Please install Pester"
            Write-Warning "     Install-Module -Name Pester -Force -SkipPublisherCheck"
            Write-Warning "     or go to https://github.com/pester/Pester"
        }
        if ($PesterVersion -lt $MinimumPesterVersion) {
            Write-Warning "Please update Pester to at least $MinimumPesterVersion"
            Write-Warning "     Install-Module -Name Pester -RequiredVersion 6.0.0 -Force -SkipPublisherCheck"
            Write-Warning "     or go to https://github.com/pester/Pester"
        }
        if ($PesterVersion -ge $MaximumPesterVersion) {
            Write-Warning "Pester $PesterVersion is newer than this runner has been tested with"
            Write-Warning "     Install-Module -Name Pester -RequiredVersion 6.0.0 -Force -SkipPublisherCheck"
            Write-Warning "     or go to https://github.com/pester/Pester"
        }

        # PSScriptAnalyzer is only consumed by the -ScriptAnalyzer and -Compliance paths, so a
        # missing or wrong-version module must not block plain test runs (e.g. on PS 5.1 where
        # another PSScriptAnalyzer version resolves first). Coverage does not use it at all.
        $ScriptAnalyzerGateOk = $true
        if ($ScriptAnalyzer -or $Compliance) {
            $ScriptAnalyzerGateOk = $HasScriptAnalyzer -and ($invokeFormatterVersion -eq $ScriptAnalyzerCorrectVersion)
        }

        if (($HasPester -and $ScriptAnalyzerGateOk -and ($PesterVersion -ge $MinimumPesterVersion) -and ($PesterVersion -lt $MaximumPesterVersion)) -eq $false) {
            Write-Warning "Exiting..."
            $stopProcess = $true
        }

        if (-not $stopProcess) {
            $ModuleBase = Get-ModuleBase
            if (-not $ModuleBase) {
                Write-Warning "Could not find dbatools.psd1 above $PSScriptRoot, exiting..."
                $stopProcess = $true
            }
        }

        if (-not $stopProcess) {
            # dbatools.psm1 only dot sources the individual files - and thereby makes the private
            # functions reachable from a test - when the module looks like a checkout. A working
            # copy that has never been cloned (a download of the source zip) has no .git, so we
            # create it. Anything without a tests folder is not a working copy at all and the test
            # paths below would silently resolve to nothing, so we refuse that instead.
            if (-not (Test-Path -Path "$ModuleBase\tests" -PathType Container)) {
                Write-Warning "$ModuleBase does not contain a tests folder, so it is not a dbatools working copy. Exiting..."
                $stopProcess = $true
            } else {
                $gitPath = Join-Path $ModuleBase ".git"
                if (-not (Test-Path $gitPath -Type Container)) {
                    $null = New-Item -Type Container -Path $gitPath -Force
                }
            }
        }

        if (-not $stopProcess) {
            Import-Module Pester -MinimumVersion $MinimumPesterVersion -ErrorAction Stop

            #removes previously imported dbatools, if any
            # No need the force will do it
            #Remove-Module dbatools -ErrorAction Ignore
            #imports the module making sure DLL is loaded ok
            Write-DetailedMessage "Importing dbatools psd1"
            Import-Module "$ModuleBase\dbatools.psd1" -DisableNameChecking -Force -NoClobber
            #imports the psm1 to be able to use internal functions in tests
            Write-DetailedMessage "Importing dbatools psm1"
            Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking -Force -NoClobber

            Write-DetailedMessage "Reading test configuration"
            $TestConfig = Get-TestConfig

            # The dbatools profile is the same set of rules the repository documents as its style.
            # Before it was passed here, -ScriptAnalyzer ran the default rule set instead, so the
            # documented behaviour and the actual behaviour were two different checks.
            $ScriptAnalyzerSettings = "$ModuleBase\tests\PSScriptAnalyzerRules.psd1"

            $testInt = [bool]$TestIntegration

            # The summary at the end is the reason these are collected rather than only reported as
            # they happen: a run over several files is unreadable if the only record of a failure is
            # a Pester report that has already scrolled past.
            $runSummary = @()
            $startTime = Get-Date
        }

        # The compliance checks belong to no command, so they run once and first. Running them first
        # also keeps the last Pester result on the pipeline the one of the last test file, which is
        # what callers that pick a single result with Select-Object -Last 1 expect.
        if (-not $stopProcess -and $Compliance) {
            Write-DetailedMessage "Running the repository wide compliance checks"
            $complianceConfig = New-PesterConfiguration
            $complianceConfig.Run.Path = "$ModuleBase\tests\dbatools.Tests.ps1"
            $complianceConfig.Run.PassThru = $true
            $complianceConfig.Output.Verbosity = $Show
            $complianceConfig.Filter.Tag = "Compliance"
            $complianceResult = Invoke-Pester -Configuration $complianceConfig

            $runSummary += [PSCustomObject]@{
                TestFileName    = "dbatools.Tests.ps1 (Compliance)"
                Result          = $complianceResult.Result
                TotalCount      = $complianceResult.TotalCount
                PassedCount     = $complianceResult.PassedCount
                FailedCount     = $complianceResult.FailedCount
                SkippedCount    = $complianceResult.SkippedCount
                DurationSeconds = [int]$complianceResult.Duration.TotalSeconds
                Failed          = $complianceResult.Failed
            }

            if ($PassThru) {
                $complianceResult
            }
        }
    }
    process {
        if ($stopProcess) {
            return
        }

        $ScriptAnalyzerRulesExclude = @("PSUseOutputTypeCorrectly", "PSAvoidUsingPlainTextForPassword", "PSUseBOMForUnicodeEncodedFile")

        $files = @()

        if ($Path) {
            foreach ($item in $path) {
                if (Test-Path $item) {
                    $files += Get-ChildItem -Path $item
                } else {
                    $files += Get-ChildItem -Path "$ModuleBase\tests\*$item*.Tests.ps1"
                }
            }
        }

        if ($files.Length -eq 0) {
            Write-Warning "No tests to be run"
        }

        $AllTestsWithinScenario = $files

        foreach ($f in $AllTestsWithinScenario) {
            if (-not (Test-PesterTestHeader -testFilePath $f.FullName)) {
                Write-Warning "$($f.Name) does not declare the mandatory Pester header, skipping it. See tests\CLAUDE.md."
                continue
            }

            # The test file is always analyzed. That is the part the old code missed: it looked at
            # the command only, so a trailing space or a misaligned splat in the test file itself
            # was never reported here and first showed up as a failing CI run.
            $AnalyzePaths = @($f.FullName)
            $CoverFiles = @()
            $HeadFunctionPath = $null

            if ($Coverage -or $ScriptAnalyzer) {
                $HeadFunctionPath = Get-CommandFile -testFilePath $f.FullName -ModuleBase $ModuleBase
                if (-not $HeadFunctionPath) {
                    Write-DetailedMessage "No command file found for $($f.Name), only the test file itself is checked"
                } else {
                    $AnalyzePaths += $HeadFunctionPath
                    $CoverFiles = @($HeadFunctionPath)
                }
            }

            if ($HeadFunctionPath -and $DependencyCoverage) {
                Write-DetailedMessage "Getting coverage indications for $f"
                $dependencyFiles = @(Get-CoverageIndications -Path $f -ModuleBase $ModuleBase) | Where-Object { $PSItem -ne $HeadFunctionPath }
                $CoverFiles += $dependencyFiles
                $AnalyzePaths += $dependencyFiles
            }

            Write-DetailedMessage "Running tests $($f.Name)"
            $pesterConfig = New-PesterConfiguration
            $pesterConfig.Run.Path = $f.FullName
            $pesterConfig.Run.PassThru = $true
            $pesterConfig.Output.Verbosity = $Show
            if ($Coverage) {
                if ($CoverFiles.Count -eq 0) {
                    Write-Warning "Cannot measure coverage for $($f.Name), no command file found for it"
                } else {
                    $pesterConfig.CodeCoverage.Enabled = $true
                    Write-DetailedMessage "We're going to target these files for coverage:"
                    foreach ($cf in $CoverFiles) {
                        Write-DetailedMessage "$cf"
                    }
                    $pesterConfig.CodeCoverage.Path = $CoverFiles
                }
            }
            if (!($testInt)) {
                $pesterConfig.Filter.ExcludeTag = "IntegrationTests"
            }
            $pesterResult = Invoke-Pester -Configuration $pesterConfig

            $runSummary += [PSCustomObject]@{
                TestFileName    = $f.Name
                Result          = $pesterResult.Result
                TotalCount      = $pesterResult.TotalCount
                PassedCount     = $pesterResult.PassedCount
                FailedCount     = $pesterResult.FailedCount
                SkippedCount    = $pesterResult.SkippedCount
                DurationSeconds = [int]$pesterResult.Duration.TotalSeconds
                Failed          = $pesterResult.Failed
            }

            if ($PassThru) {
                $pesterResult
            }

            if ($ScriptAnalyzer) {
                if ($Show -ne "None") {
                    Write-Host -ForegroundColor Green -Object "ScriptAnalyzer check for $($AnalyzePaths -join ", ")"
                }
                # -Path takes a single file, so the list is walked rather than passed as an array
                foreach ($analyzePath in $AnalyzePaths) {
                    $splatAnalyzer = @{
                        Path        = $analyzePath
                        Settings    = $ScriptAnalyzerSettings
                        ExcludeRule = $ScriptAnalyzerRulesExclude
                    }
                    Invoke-ScriptAnalyzer @splatAnalyzer
                }
            }
        }
    }
    end {
        if ($stopProcess -or $runSummary.Count -eq 0 -or $Show -eq "None") {
            return
        }

        Write-Host "`n$("=" * 60)"
        Write-Host "Ran $($runSummary.Count) test files in $([int]((Get-Date) - $startTime).TotalSeconds) seconds"
        $runSummary | Format-Table -Property TestFileName, Result, TotalCount, PassedCount, FailedCount, SkippedCount, DurationSeconds -AutoSize | Out-Host

        foreach ($summary in $runSummary | Where-Object FailedCount -gt 0) {
            Write-Host "$($summary.TestFileName)" -ForegroundColor Yellow
            foreach ($failedTest in $summary.Failed) {
                Write-Host "  FAILED  $($failedTest.ExpandedPath)"
                if ($failedTest.ErrorRecord.TargetObject.Line) {
                    Write-Host "          line $($failedTest.ErrorRecord.TargetObject.Line): $($failedTest.ErrorRecord.TargetObject.LineText.Trim())"
                }
                $failedMessage = ($failedTest.ErrorRecord.Exception.Message -split "`n" | ForEach-Object { $PSItem.Trim() }) -join " "
                Write-Host "          $failedMessage"
            }
        }

        # The style gate that CI runs is not part of any command's test file, so a run without it
        # can be green here and still fail the pipeline. Say so rather than let it be discovered
        # in the pull request.
        if (-not $Compliance) {
            Write-Host "`nThe repository wide style checks did not run. Add -Compliance before opening a pull request." -ForegroundColor Cyan
        }
    }
}
