<#
.SYNOPSIS
This script will invoke Pester tests, then serialize XML results and pull them in appveyor.yml

.DESCRIPTION
Internal function that runs pester tests

.PARAMETER Finalize
If Finalize is specified, we collect XML output, upload tests, and indicate build errors

.PARAMETER PSVersion
The version of PS

.PARAMETER TestFile
The output file

.PARAMETER ProjectRoot
The appveyor project root

.PARAMETER ModuleBase
The location of the module

.PARAMETER IncludeCoverage
Calculates coverage and sends it to codecov.io

.PARAMETER DebugErrorExtraction
Enables ultra-verbose error message extraction with comprehensive debugging information.
This will extract ALL properties from test results and provide detailed exception information.
Use this when you need to "try hard as hell to get the error message" with maximum fallbacks.

.EXAMPLE
.\appveyor.pester.ps1
Executes the test

.EXAMPLE
.\appveyor.pester.ps1 -Finalize
Finalizes the tests

.EXAMPLE
.\appveyor.pester.ps1 -DebugErrorExtraction
Executes tests with ultra-verbose error extraction for maximum error message capture

.EXAMPLE
.\appveyor.pester.ps1 -Finalize -DebugErrorExtraction
Finalizes tests with comprehensive error message extraction and debugging
#>
param (
    [switch]$Finalize,
    $PSVersion = $PSVersionTable.PSVersion.Major,
    $TestFile = "TestResultsPS$PSVersion.xml",
    $ProjectRoot = $env:APPVEYOR_BUILD_FOLDER,
    $ModuleBase = $ProjectRoot,
    [switch]$IncludeCoverage,
    [switch]$DebugErrorExtraction
)

# Move to the project root
Set-Location $ModuleBase
# required to calculate coverage
$global:dbatools_dotsourcemodule = $true
# imports the psm1 to be able to use internal functions in tests
Import-Module "$ModuleBase\dbatools.psm1" -Force

# Ensure ShouldProcess/ConfirmImpact=High commands work non-interactively in CI
# $PSDefaultParameterValues['*-Dba*:Confirm'] = $false does not reliably propagate
# into Pester 5 isolated scopes, so we suppress globally here
$global:ConfirmPreference = 'None'

function Split-ArrayInParts($array, [int]$parts) {
    #splits an array in "equal" parts
    $size = $array.Length / $parts
    $counter = [PSCustomObject] @{ Value = 0 }
    $groups = $array | Group-Object -Property { [math]::Floor($counter.Value++ / $size) }
    $rtn = @()
    foreach ($g in $groups) {
        $rtn += , @($g.Group)
    }
    $rtn
}

function Get-CoverageIndications($Path, $ModuleBase) {
    # takes a test file path and figures out what to analyze for coverage (i.e. dependencies)
    $CBHRex = [regex]'(?smi)<#(.*)#>'
    $everything = (Get-Module dbatools).ExportedCommands.Values
    $everyfunction = $everything.Name
    $funcs = @()
    $leaf = Split-Path $path -Leaf
    # assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
    # but allowing also Get-DbaFoo.one.Tests.ps1 and Get-DbaFoo.two.Tests.ps1
    $func_name += ($leaf -replace '^([^.]+)(.+)?.Tests.ps1', '$1')
    if ($func_name -in $everyfunction) {
        $funcs += $func_name
        $f = $everything | Where-Object Name -eq $func_name
        $source = $f.Definition
        $CBH = $CBHRex.match($source).Value
        # This fails very hard sometimes
        if ($source -and $CBH) {
            $cmdonly = $source.Replace($CBH, '')
            foreach ($e in $everyfunction) {
                # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
                $searchme = "$e "
                if ($cmdonly.contains($searchme)) {
                    $funcs += $e
                }
            }
        }
    }
    $testpaths = @()
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\private\functions", "$ModuleBase\public" -Filter '*.ps1'
    foreach ($f in $funcs) {
        # exclude always used functions ?!
        if ($f -in ('Connect-DbaInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
        # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
        $res = $allfiles | Where-Object { $PSItem.Name.Replace('.ps1', '') -eq $f }
        if ($res.count -gt 0) {
            $testpaths += $res.FullName
        }
    }
    return @() + ($testpaths | Select-Object -Unique)
}

function Get-CodecovReport($Results, $ModuleBase) {
    #handle coverage https://docs.codecov.io/reference#upload
    $report = @{'coverage' = @{ } }
    #needs correct casing to do the replace
    $ModuleBase = (Resolve-Path $ModuleBase).Path
    # things we wanna a report for (and later backfill if not tested)
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\private\functions", "$ModuleBase\public" -Filter '*.ps1'

    $missed = $results.CodeCoverage | Select-Object -ExpandProperty MissedCommands | Sort-Object -Property File, Line -Unique
    $hits = $results.CodeCoverage | Select-Object -ExpandProperty HitCommands | Sort-Object -Property File, Line -Unique
    $LineCount = @{ }
    $hits | ForEach-Object {
        $filename = $PSItem.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{ }
            $LineCount[$filename] = (Get-Content $PSItem.File -Raw | Measure-Object -Line).Lines
        }
        $report['coverage'][$filename][$PSItem.Line] = 1
    }

    $missed | ForEach-Object {
        $filename = $PSItem.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{ }
            $LineCount[$filename] = (Get-Content $PSItem.File | Measure-Object -Line).Lines
        }
        if ($PSItem.Line -notin $report['coverage'][$filename].Keys) {
            #miss only if not already covered
            $report['coverage'][$filename][$PSItem.Line] = 0
        }
    }

    $newreport = @{'coverage' = [ordered]@{ } }
    foreach ($fname in $report['coverage'].Keys) {
        $Linecoverage = [ordered]@{ }
        for ($i = 1; $i -le $LineCount[$fname]; $i++) {
            if ($i -in $report['coverage'][$fname].Keys) {
                $Linecoverage["$i"] = $report['coverage'][$fname][$i]
            }
        }
        $newreport['coverage'][$fname] = $Linecoverage
    }

    #backfill it
    foreach ($target in $allfiles) {
        $target_relative = $target.FullName.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($target_relative -notin $newreport['coverage'].Keys) {
            $newreport['coverage'][$target_relative] = @{"1" = $null }
        }
    }
    $newreport
}


function Get-ComprehensiveErrorMessage {
    param(
        $TestResult,
        [switch]$DebugMode
    )

    $errorMessages = @()
    $stackTraces = @()
    $debugInfo = @()

    try {
        # Pester 5 error extraction with multiple fallbacks
        if ($TestResult.ErrorRecord -and $TestResult.ErrorRecord.Count -gt 0) {
            foreach ($errorRec in $TestResult.ErrorRecord) {
                if ($errorRec.Exception) {
                    $errorMessages += $errorRec.Exception.Message
                    if ($errorRec.Exception.InnerException) {
                        $errorMessages += "Inner: $($errorRec.Exception.InnerException.Message)"
                    }

                    # Debug mode: extract more exception details
                    if ($DebugMode) {
                        if ($errorRec.Exception.GetType) {
                            $debugInfo += "ExceptionType: $($errorRec.Exception.GetType().FullName)"
                        }
                        if ($errorRec.Exception.HResult) {
                            $debugInfo += "HResult: $($errorRec.Exception.HResult)"
                        }
                        if ($errorRec.Exception.Source) {
                            $debugInfo += "Source: $($errorRec.Exception.Source)"
                        }
                    }
                }
                if ($errorRec.ScriptStackTrace) {
                    $stackTraces += $errorRec.ScriptStackTrace
                }
                if ($errorRec.StackTrace) {
                    $stackTraces += $errorRec.StackTrace
                }
                if ($errorRec.FullyQualifiedErrorId) {
                    $errorMessages += "ErrorId: $($errorRec.FullyQualifiedErrorId)"
                }

                # Debug mode: extract more ErrorRecord details
                if ($DebugMode) {
                    if ($errorRec.CategoryInfo) {
                        $debugInfo += "Category: $($errorRec.CategoryInfo.Category)"
                        $debugInfo += "Activity: $($errorRec.CategoryInfo.Activity)"
                        $debugInfo += "Reason: $($errorRec.CategoryInfo.Reason)"
                        $debugInfo += "TargetName: $($errorRec.CategoryInfo.TargetName)"
                    }
                    if ($errorRec.InvocationInfo) {
                        $debugInfo += "ScriptName: $($errorRec.InvocationInfo.ScriptName)"
                        $debugInfo += "Line: $($errorRec.InvocationInfo.ScriptLineNumber)"
                        $debugInfo += "Command: $($errorRec.InvocationInfo.MyCommand)"
                    }
                }
            }
        }

        if ($TestResult.FailureMessage) {
            $errorMessages += $TestResult.FailureMessage
        }

        if ($TestResult.StackTrace) {
            $stackTraces += $TestResult.StackTrace
        }

        # Try StandardOutput and StandardError if available
        if ($TestResult.StandardOutput) {
            $errorMessages += "StdOut: $($TestResult.StandardOutput)"
        }
        if ($TestResult.StandardError) {
            $errorMessages += "StdErr: $($TestResult.StandardError)"
        }

        # Check Block.ErrorRecord for container-level errors (common in Pester 5)
        if ($TestResult.Block -and $TestResult.Block.ErrorRecord) {
            foreach ($blockError in $TestResult.Block.ErrorRecord) {
                if ($blockError.Exception) {
                    $errorMessages += "Block Error: $($blockError.Exception.Message)"
                }
            }
        }

        # Check for Should assertion details in Data property
        if ($TestResult.Data -and $TestResult.Data.Count -gt 0) {
            $errorMessages += "Test Data: $($TestResult.Data | ConvertTo-Json -Compress)"
        }

        # Fallback: try to extract from any property that might contain error info
        $TestResult.PSObject.Properties | ForEach-Object {
            if ($PSItem.Name -match '(?i)(error|exception|failure|message)' -and $PSItem.Value -and $PSItem.Value -ne '') {
                if ($PSItem.Value -notin $errorMessages) {
                    $errorMessages += "$($PSItem.Name): $($PSItem.Value)"
                }
            }
        }

        # Debug mode: extract ALL properties for ultra-verbose debugging
        if ($DebugMode) {
            $debugInfo += "=== ALL TEST RESULT PROPERTIES ==="
            $TestResult.PSObject.Properties | ForEach-Object {
                try {
                    $value = if ($null -eq $PSItem.Value) { "NULL" } elseif ($PSItem.Value -eq "") { "EMPTY" } else { $PSItem.Value.ToString() }
                    if ($value.Length -gt 200) { $value = $value.Substring(0, 200) + "..." }
                    $debugInfo += "$($PSItem.Name): $value"
                } catch {
                    $debugInfo += "$($PSItem.Name): [Error getting value: $($PSItem.Exception.Message)]"
                }
            }
        }

    } catch {
        $errorMessages += "Error during error extraction: $($PSItem.Exception.Message)"
    }

    # Final fallback
    if ($errorMessages.Count -eq 0) {
        $errorMessages += "Test failed but no error message could be extracted. Result: $($TestResult.Result)"
        if ($TestResult.Name) {
            $errorMessages += "Test Name: $($TestResult.Name)"
        }

        # Debug mode: try one last desperate attempt
        if ($DebugMode) {
            $errorMessages += "=== DESPERATE DEBUG ATTEMPT ==="
            try {
                $errorMessages += "TestResult JSON: $($TestResult | ConvertTo-Json -Depth 2 -Compress)"
            } catch {
                $errorMessages += "Could not serialize TestResult to JSON: $($PSItem.Exception.Message)"
            }
        }
    }

    # Combine debug info if in debug mode
    if ($DebugMode -and $debugInfo.Count -gt 0) {
        $errorMessages += "=== DEBUG INFO ==="
        $errorMessages += $debugInfo
    }

    return @{
        ErrorMessage = ($errorMessages | Where-Object { $PSItem } | Select-Object -Unique) -join " | "
        StackTrace   = ($stackTraces | Where-Object { $PSItem } | Select-Object -Unique) -join "`n---`n"
    }
}

function Export-TestFailureSummary {
    param(
        $TestFile,
        $PesterRun,
        $Counter,
        $ModuleBase
    )

    $failedTests = @()

    # Pester 5 format
    $failedTests = $PesterRun.Tests | Where-Object { $PSItem.Passed -eq $false } | ForEach-Object {
        # Extract line number from stack trace
        $lineNumber = $null
        $stackTrace = ""

        if ($PSItem.ErrorRecord -and $PSItem.ErrorRecord.Count -gt 0 -and $PSItem.ErrorRecord[0].ScriptStackTrace) {
            $stackTrace = $PSItem.ErrorRecord[0].ScriptStackTrace
            if ($stackTrace -match 'line (\d+)') {
                $lineNumber = [int]$Matches[1]
            }
        }

        # Get comprehensive error message with fallbacks
        $errorInfo = Get-ComprehensiveErrorMessage -TestResult $PSItem -DebugMode:$DebugErrorExtraction

        @{
            Name          = $PSItem.Name
            Describe      = if ($PSItem.Path.Count -gt 0) { $PSItem.Path[0] } else { "" }
            Context       = if ($PSItem.Path.Count -gt 1) { $PSItem.Path[1] } else { "" }
            ErrorMessage  = $errorInfo.ErrorMessage
            StackTrace    = if ($errorInfo.StackTrace) { $errorInfo.StackTrace } else { $stackTrace }
            LineNumber    = $lineNumber
            Parameters    = $PSItem.Data
            TestFile      = $TestFile.Name
            RawTestResult = $PSItem | ConvertTo-Json -Depth 3 -Compress
        }
    }

    if ($failedTests.Count -gt 0) {
        $summary = @{
            TestFile      = $TestFile.Name
            PesterVersion = "5"
            TotalTests    = $PesterRun.TotalCount
            PassedTests   = $PesterRun.PassedCount
            FailedTests   = $PesterRun.FailedCount
            Duration      = $PesterRun.Duration.TotalMilliseconds
            Failures      = $failedTests
        }

        $summaryFile = "$ModuleBase\TestFailureSummary_Pester5_${Counter}.json"
        $summary | ConvertTo-Json -Depth 10 | Out-File $summaryFile -Encoding UTF8
        Push-AppveyorArtifact $summaryFile -FileName "TestFailureSummary_Pester5_${Counter}.json"
    }
}

if (-not $Finalize) {
    # Invoke appveyor.common.ps1 to know which tests to run
    . "$ModuleBase\tests\appveyor.common.ps1"
    $AllScenarioTests = Get-TestsForBuildScenario -ModuleBase $ModuleBase

    # Run a test with the current version of PowerShell
    # Make things faster by removing most output
    Set-Variable ProgressPreference -Value SilentlyContinue
    if ($AllScenarioTests.Count -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Nothing to do in this scenario"
        return
    }

    # Remove any previously loaded pester module
    Remove-Module -Name Pester -ErrorAction SilentlyContinue
    # Import pester 5
    Import-Module -Name Pester -RequiredVersion 5.7.1
    Write-Host -Object "appveyor.pester: Running with Pester Version $((Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version)" -ForegroundColor DarkGreen

    # invoking a single invoke-pester consumes too much memory, let's go file by file
    $AllTestsWithinScenario = Get-ChildItem -File -Path $AllScenarioTests | Sort-Object Name

    # Create a summary file for all test runs
    $allTestsSummary = @{
        Scenario = $env:SCENARIO
        Part     = $env:PART
        TestRuns = @()
    }

    $TestConfig = Get-TestConfig
    $Counter = 0
    foreach ($f in $AllTestsWithinScenario) {
        $Counter += 1

        $pester5Config = New-PesterConfiguration
        $pester5Config.Run.Path = $f.FullName
        $pester5config.Run.PassThru = $true
        $pester5config.Output.Verbosity = "None"

        #opt-in
        if ($IncludeCoverage) {
            $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
            $pester5Config.CodeCoverage.Enabled = $true
            $pester5Config.CodeCoverage.Path = $CoverFiles
            $pester5Config.CodeCoverage.OutputFormat = 'JaCoCo'
            $pester5Config.CodeCoverage.OutputPath = "$ModuleBase\Pester5Coverage$PSVersion$Counter.xml"
        }

        $trialNo = 1
        while ($trialNo -le 3) {
            if ($trialNo -eq 1) {
                $appvTestName = $f.Name
            } else {
                $appvTestName = "$($f.Name), attempt #$trialNo"
            }
            Write-Host -Object "Running $($f.FullName) ..." -ForegroundColor Cyan -NoNewLine
            Add-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome Running
            $PesterRun = Invoke-Pester -Configuration $pester5config
            Write-Host -Object "`rCompleted $($f.FullName) in $([int]$PesterRun.Duration.TotalMilliseconds)ms" -ForegroundColor Cyan
            $PesterRun | Export-Clixml -Path "$ModuleBase\Pester5Results$PSVersion$Counter.xml"

            # Export failure summary for easier retrieval
            Export-TestFailureSummary -TestFile $f -PesterRun $PesterRun -Counter $Counter -ModuleBase $ModuleBase

            if ($PesterRun.FailedCount -gt 0) {
                $trialno += 1

                # Create detailed error message for AppVeyor with comprehensive extraction
                $failedTestsList = $PesterRun.Tests | Where-Object { $PSItem.Passed -eq $false } | ForEach-Object {
                    $path = $PSItem.Path -join " > "
                    $errorInfo = Get-ComprehensiveErrorMessage -TestResult $PSItem -DebugMode:$DebugErrorExtraction
                    "$path > $($PSItem.Name): $($errorInfo.ErrorMessage)"
                }
                $errorMessageDetail = $failedTestsList -join " | "

                if ($trialNo -le 3) {
                    Write-Host -Object "appveyor.pester: Test failed with $($PesterRun.FailedCount) failed tests. Retrying (attempt $trialNo of 3)..." -ForegroundColor Yellow
                    # Restarting all used instances to avoid state issues
                    $null = Get-DbaService -Type Engine | Where-Object State -eq 'Running' | Restart-DbaService -Force -Confirm:$false
                    Start-Sleep -Seconds 10
                    # Clean up registered server test artifacts to prevent UNIQUE KEY violations on retry
                    try {
                        $splatCleanup = @{
                            Type        = 'Engine'
                            ErrorAction = 'SilentlyContinue'
                        }
                        $cleanupInstances = Get-DbaService @splatCleanup |
                            Where-Object State -eq 'Running' |
                            Select-Object -ExpandProperty InstanceName |
                            ForEach-Object { "$(hostname)\$_" }
                        foreach ($inst in $cleanupInstances) {
                            $srv = Connect-DbaInstance -SqlInstance $inst -ErrorAction SilentlyContinue
                            if ($srv) {
                                $srv.Query("DELETE FROM msdb.dbo.sysmanagement_shared_registered_servers_internal WHERE name LIKE 'dbatoolsci%'")
                                $srv.Query("DELETE FROM msdb.dbo.sysmanagement_shared_server_groups_internal WHERE name LIKE 'dbatoolsci%'")
                            }
                        }
                        Write-Host -Object "appveyor.pester: Cleaned up registered server test artifacts" -ForegroundColor DarkGreen
                    } catch {
                        Write-Host -Object "appveyor.pester: Cleanup of registered server artifacts failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host -Object "appveyor.pester: Test failed with $($PesterRun.FailedCount) failed tests. No more retries left." -ForegroundColor Red
                    Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Failed" -Duration $PesterRun.Duration.TotalMilliseconds -ErrorMessage $errorMessageDetail
                }

                # Add to summary
                $allTestsSummary.TestRuns += @{
                    TestFile      = $f.Name
                    Attempt       = $trialNo
                    Outcome       = "Failed"
                    FailedCount   = $PesterRun.FailedCount
                    Duration      = $PesterRun.Duration.TotalMilliseconds
                    PesterVersion = '5'
                }
            } else {
                Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Passed" -Duration $PesterRun.Duration.TotalMilliseconds

                # Add to summary
                $allTestsSummary.TestRuns += @{
                    TestFile      = $f.Name
                    Attempt       = $trialNo
                    Outcome       = "Passed"
                    Duration      = $PesterRun.Duration.TotalMilliseconds
                    PesterVersion = '5'
                }
                break
            }
        }
    }

    # Save overall test summary
    $summaryFile = "$ModuleBase\OverallTestSummary.json"
    $allTestsSummary | ConvertTo-Json -Depth 10 | Out-File $summaryFile -Encoding UTF8
    Push-AppveyorArtifact $summaryFile -FileName "OverallTestSummary.json"

    # Gather support package as an artifact
    # New-DbatoolsSupportPackage -Path $ModuleBase - turns out to be too heavy
    try {
        $msgFile = "$ModuleBase\dbatools_messages.xml"
        $errorFile = "$ModuleBase\dbatools_errors.xml"
        Write-Host -ForegroundColor DarkGreen "Dumping message log into $msgFile"
        Get-DbatoolsLog | Select-Object FunctionName, Level, TimeStamp, Message | Export-Clixml -Path $msgFile -ErrorAction Stop
        Write-Host -ForegroundColor Yellow "Skipping dump of error log into $errorFile"
        try {
            # Uncomment this when needed
            #Get-DbatoolsError -All -ErrorAction Stop | Export-Clixml -Depth 1 -Path $errorFile -ErrorAction Stop
        } catch {
            Set-Content -Path $errorFile -Value 'Uncomment line 386 in appveyor.pester.ps1 if needed'
        }
        if (-not (Test-Path $errorFile)) {
            Set-Content -Path $errorFile -Value 'None'
        }
        Compress-Archive -Path $msgFile, $errorFile -DestinationPath "dbatools_messages_and_errors.xml.zip" -ErrorAction Stop
        Remove-Item $msgFile
        Remove-Item $errorFile
    } catch {
        Write-Host -ForegroundColor Red "Message collection failed: $($PSItem.Exception.Message)"
    }
} else {
    # $Finalize = $true

    # Publish the support package regardless of the outcome
    if (Test-Path $ModuleBase\dbatools_messages_and_errors.xml.zip) {
        Get-ChildItem $ModuleBase\dbatools_messages_and_errors.xml.zip | ForEach-Object { Push-AppveyorArtifact $PSItem.FullName -FileName $PSItem.Name }
    }

    # What failed? How many tests did we run ?
    $results = @(Get-ChildItem -Path "$ModuleBase\Pester5Results*.xml" | Import-Clixml)
    $failedcount = $results | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $faileditems = $results | Select-Object -ExpandProperty Tests | Where-Object { $PSItem.Passed -notlike $True }
    if ($faileditems) {
        Write-Warning "Failed tests summary:"
        $detailedFailures = $faileditems | ForEach-Object {
            $name = $PSItem.Name

            # Use comprehensive error extraction for finalization too
            $errorInfo = Get-ComprehensiveErrorMessage -TestResult $PSItem -DebugMode:$DebugErrorExtraction

            [PSCustomObject]@{
                Path           = $PSItem.Path -Join '/'
                Name           = "It $name"
                Result         = $PSItem.Result
                Message        = $errorInfo.ErrorMessage
                StackTrace     = $errorInfo.StackTrace
                RawErrorRecord = if ($PSItem.ErrorRecord) { $PSItem.ErrorRecord -Join " | " } else { "No ErrorRecord" }
            }
        } | Sort-Object Path, Name, Result, Message

        $detailedFailures | Format-List

        # Save detailed failure information as artifact
        $detailedFailureSummary = @{
            PesterVersion    = "5"
            TotalFailedTests = $faileditems.Count
            DetailedFailures = $detailedFailures | ForEach-Object {
                @{
                    TestPath       = $PSItem.Path
                    TestName       = $PSItem.Name
                    Result         = $PSItem.Result
                    ErrorMessage   = $PSItem.Message
                    StackTrace     = $PSItem.StackTrace
                    RawErrorRecord = $PSItem.RawErrorRecord
                    FullContext    = "$($PSItem.Path) > $($PSItem.Name)"
                }
            }
        }

        $detailedFailureFile = "$ModuleBase\DetailedTestFailures_Pester5.json"
        $detailedFailureSummary | ConvertTo-Json -Depth 10 | Out-File $detailedFailureFile -Encoding UTF8
        Push-AppveyorArtifact $detailedFailureFile -FileName "DetailedTestFailures_Pester5.json"

        throw "$failedcount tests failed."
    }
}