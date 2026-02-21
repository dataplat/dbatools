function Start-ParallelPester {
    <#
    .SYNOPSIS
        Runs Pester test files in parallel using PowerShell Runspaces.

    .DESCRIPTION
        Creates a runspace pool and executes Pester test files concurrently.
        Test files are split into $MaxThreads batches, and each batch runs in
        its own isolated runspace. Each runspace imports dbatools, Pester, and
        creates its own $TestConfig once, then runs all tests in its batch
        sequentially. Results are streamed to the pipeline as each test
        completes within a runspace.

        No retry logic is included — callers should collect failures and retry
        them sequentially (with SQL service restarts if needed).

    .PARAMETER TestFiles
        Array of test file objects (FileInfo) to run.

    .PARAMETER ModuleBase
        Path to the dbatools module root directory.

    .PARAMETER MaxThreads
        Maximum number of concurrent runspaces. Default is 3.

    .PARAMETER MaxErrors
        Bail out after this many test files have failures. Default is 10.

    .OUTPUTS
        PSCustomObject with properties:
            TestFile, TestFileName, PassedCount, FailedCount, SkippedCount,
            Duration, Result, Tests, PesterRun, RunspaceError

    .EXAMPLE
        $results = Start-ParallelPester -TestFiles $testFiles -ModuleBase "C:\github\dbatools"

    .NOTES
        Author: the dbatools team + Claude
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TestFiles,

        [Parameter(Mandatory)]
        [string]$ModuleBase,

        [int]$MaxThreads = 3,

        [int]$MaxErrors = 10
    )

    $parallelStartTime = Get-Date
    $totalTests = $TestFiles.Count

    # Split an array into roughly equal parts — used to batch test files into $MaxThreads groups
    # so each runspace imports the module once and runs its batch sequentially.
    function Split-ArrayInParts($array, [int]$parts) {
        #splits an array in "equal" parts
        $size = $array.Length / $parts
        if ($size -lt 1) { $size = 1 }
        $counter = [PSCustomObject] @{ Value = 0 }
        $groups = $array | Group-Object -Property { [math]::Floor($counter.Value++ / $size) }
        $rtn = @()
        foreach ($g in $groups) {
            $rtn += , @($g.Group)
        }
        $rtn
    }

    # Split test files into $MaxThreads batches — each batch runs in one runspace,
    # importing the module only once instead of once per test file.
    $batches = Split-ArrayInParts -array $TestFiles -parts $MaxThreads
    $batchCount = $batches.Count

    Write-Host -Object "Start-ParallelPester: Running $totalTests test files in $batchCount batches with $MaxThreads max concurrent threads" -ForegroundColor DarkGreen

    # Scriptblock that executes inside each isolated runspace.
    # Runspaces share NO state with the caller — modules, variables, and functions
    # must all be set up from scratch.
    $scriptblock = {
        param(
            [string[]]$TestFilePaths,
            [string]$ModuleBasePath,
            [bool]$DotSourceModule
        )

        # Import dbatools — runspaces are isolated, nothing is inherited
        $global:dbatools_dotsourcemodule = $DotSourceModule
        Import-Module "$ModuleBasePath\dbatools.psm1" -Force
        $global:ConfirmPreference = 'None'

        # Import Pester
        Remove-Module -Name Pester -ErrorAction SilentlyContinue
        Import-Module -Name Pester -RequiredVersion 5.7.1

        # Create TestConfig inside this runspace — test files reference $TestConfig
        # in their param() default values, so it must be in scope.
        $global:TestConfig = Get-TestConfig

        foreach ($testFile in $TestFilePaths) {
            $pesterConfig = New-PesterConfiguration
            $pesterConfig.Run.Path = $testFile
            $pesterConfig.Run.PassThru = $true
            $pesterConfig.Output.Verbosity = "None"

            try {
                $run = Invoke-Pester -Configuration $pesterConfig

                [PSCustomObject]@{
                    TestFile      = $testFile
                    TestFileName  = [System.IO.Path]::GetFileName($testFile)
                    PassedCount   = $run.PassedCount
                    FailedCount   = $run.FailedCount
                    SkippedCount  = $run.SkippedCount
                    Duration      = $run.Duration
                    Result        = $run.Result
                    Tests         = $run.Tests
                    PesterRun     = $run
                    RunspaceError = $null
                }
            } catch {
                [PSCustomObject]@{
                    TestFile      = $testFile
                    TestFileName  = [System.IO.Path]::GetFileName($testFile)
                    PassedCount   = 0
                    FailedCount   = 1
                    SkippedCount  = 0
                    Duration      = [TimeSpan]::Zero
                    Result        = "Failed"
                    Tests         = @()
                    PesterRun     = $null
                    RunspaceError = $PSItem.Exception.Message
                }
            }
        }
    }

    # Create runspace pool
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $pool.ApartmentState = "MTA"
    $pool.Open()

    $runspaces = @()
    $allResults = @()
    $errorCount = 0
    $completedCount = 0

    try {
        # Queue one runspace per batch — each imports the module once and runs its tests sequentially
        foreach ($batch in $batches) {
            $ps = [PowerShell]::Create()
            $null = $ps.AddScript($scriptblock)
            $null = $ps.AddArgument(@($batch | ForEach-Object { $PSItem.FullName }))
            $null = $ps.AddArgument($ModuleBase)
            $null = $ps.AddArgument($true)
            $ps.RunspacePool = $pool

            $runspaces += [PSCustomObject]@{
                Pipe      = $ps
                Status    = $ps.BeginInvoke()
                TestFiles = $batch
            }
        }

        Write-Host -Object "Start-ParallelPester: All $batchCount runspaces queued, waiting for completion..." -ForegroundColor DarkGreen

        # Poll for completion and stream results
        while ($runspaces.Count -gt 0) {
            foreach ($rs in @($runspaces)) {
                if ($rs.Status.IsCompleted) {
                    try {
                        $result = $rs.Pipe.EndInvoke($rs.Status)

                        # Check for runspace-level errors (module import failures, etc.)
                        if ($rs.Pipe.Streams.Error.Count -gt 0) {
                            $batchNames = ($rs.TestFiles | ForEach-Object { $PSItem.Name }) -join ", "
                            $runspaceErrors = ($rs.Pipe.Streams.Error | ForEach-Object { $PSItem.ToString() }) -join " | "
                            Write-Warning "Runspace error for batch ($batchNames): $runspaceErrors"
                        }

                        if ($result) {
                            foreach ($r in $result) {
                                $completedCount++
                                if ($r.FailedCount -gt 0) {
                                    $errorCount++
                                    Write-Host -Object "  FAILED [$completedCount/$totalTests]: $($r.TestFileName) ($($r.FailedCount) failures in $([int]$r.Duration.TotalMilliseconds)ms)" -ForegroundColor Red
                                } elseif ($r.RunspaceError) {
                                    $errorCount++
                                    Write-Host -Object "  ERROR  [$completedCount/$totalTests]: $($r.TestFileName) - $($r.RunspaceError)" -ForegroundColor Red
                                } else {
                                    Write-Host -Object "  Passed [$completedCount/$totalTests]: $($r.TestFileName) ($([int]$r.Duration.TotalMilliseconds)ms)" -ForegroundColor DarkGreen
                                }
                                $allResults += $r
                                $r  # output to pipeline
                            }
                        }
                    } catch {
                        # EndInvoke threw — create error results for all files in the batch
                        foreach ($batchFile in $rs.TestFiles) {
                            $completedCount++
                            $errorCount++
                            $errorResult = [PSCustomObject]@{
                                TestFile      = $batchFile.FullName
                                TestFileName  = $batchFile.Name
                                PassedCount   = 0
                                FailedCount   = 1
                                SkippedCount  = 0
                                Duration      = [TimeSpan]::Zero
                                Result        = "Failed"
                                Tests         = @()
                                PesterRun     = $null
                                RunspaceError = $PSItem.Exception.Message
                            }
                            Write-Host -Object "  ERROR  [$completedCount/$totalTests]: $($batchFile.Name) - $($PSItem.Exception.Message)" -ForegroundColor Red
                            $allResults += $errorResult
                            $errorResult  # output to pipeline
                        }
                    } finally {
                        $rs.Pipe.Dispose()
                        $runspaces = @($runspaces | Where-Object { $_ -ne $rs })
                    }
                }
            }

            # Bail-out if too many failures
            if ($errorCount -ge $MaxErrors) {
                Write-Host -Object "Start-ParallelPester: Bailing out after $errorCount test file failures (max $MaxErrors)" -ForegroundColor Red
                foreach ($rs in $runspaces) {
                    try {
                        $rs.Pipe.Stop()
                        $rs.Pipe.Dispose()
                    } catch {
                        # ignore cleanup errors
                    }
                }
                $runspaces = @()
                break
            }

            if ($runspaces.Count -gt 0) {
                Start-Sleep -Milliseconds 100
            }
        }
    } finally {
        # Ensure all runspaces are cleaned up
        foreach ($rs in $runspaces) {
            try {
                $rs.Pipe.Stop()
                $rs.Pipe.Dispose()
            } catch {
                # ignore cleanup errors
            }
        }

        # Close and dispose the pool
        try {
            $pool.Close()
            $pool.Dispose()
        } catch {
            Write-Warning "Error closing runspace pool: $($PSItem.Exception.Message)"
        }
    }

    # Report timing statistics
    $parallelEndTime = Get-Date
    $wallClockSeconds = ($parallelEndTime - $parallelStartTime).TotalSeconds
    $cumulativeSeconds = ($allResults | ForEach-Object { $PSItem.Duration.TotalSeconds } | Measure-Object -Sum).Sum

    $totalPassed = ($allResults | Measure-Object -Property PassedCount -Sum).Sum
    $totalFailed = ($allResults | Measure-Object -Property FailedCount -Sum).Sum
    $totalSkipped = ($allResults | Measure-Object -Property SkippedCount -Sum).Sum

    Write-Host -Object "Start-ParallelPester: $totalPassed passed, $totalFailed failed, $totalSkipped skipped" -ForegroundColor $(if ($totalFailed -gt 0) { "Red" } else { "DarkGreen" })
    Write-Host -Object "Start-ParallelPester: Wall-clock $([int]$wallClockSeconds)s vs cumulative $([int]$cumulativeSeconds)s" -ForegroundColor DarkGreen
    if ($cumulativeSeconds -gt 0) {
        $timeSaved = $cumulativeSeconds - $wallClockSeconds
        if ($timeSaved -gt 0) {
            $percentSaved = [int](($timeSaved / $cumulativeSeconds) * 100)
            Write-Host -Object "Start-ParallelPester: Saved $([int]$timeSaved)s ($percentSaved% faster)" -ForegroundColor DarkGreen
        }
    }
}
