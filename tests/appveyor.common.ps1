function Get-TestsForScenario {
    param($Scenario, $AllTest, [switch]$Silent)

    # does this scenario run an 'autodetect' ?
    if ($TestsRunGroups[$Scenario].StartsWith('autodetect_')[0]) {
        # exclude any test specifically tied to a non-autodetect scenario
        $TiedFunctions = ($TestsRunGroups.GetEnumerator() | Where-Object { $_.Value -notlike 'autodetect_*' }).Value
        $RemainingTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TiedFunctions }
        # and now scan for the instance string
        $ScanFor = $TestsRunGroups[$Scenario].Replace('autodetect_', '')
        #if ScanFor holds an array, search it in *and*
        $ScanForAll = $ScanFor.Split(',')
        # and exclude other instances in autodetect
        $ExcludeScanForRaw = @() + ($TestsRunGroups.GetEnumerator() | Where-Object { ($_.Name -ne $Scenario) -and ($_.Value -like 'autodetect_*') }).Value.Replace('autodetect_', '')
        $ScanTests = @()
        foreach ($test in $RemainingTests) {
            $testcontent = Get-Content $test -Raw
            $IncludeFlag = 0
            foreach ($piece in $ScanForAll) {
                if ($testcontent -like "*$piece*") {
                    $IncludeFlag += 1
                }
            }
            if ($IncludeFlag -eq $ScanForAll.Length) {
                #matched all pieces
                $ExcludeAll = 0
                foreach ($otherenv in $ExcludeScanForRaw) {
                    $ExcludeFlag = 0
                    $ExcludeScanForAll_ = $otherenv.split(',')
                    #honor includes before excludes
                    $ExcludeScanForAll = @()
                    foreach ($piece in $ExcludeScanForAll_) {
                        if ($piece -notin $ScanForAll) {
                            $ExcludeScanForAll += $piece
                        }
                    }
                    if ($ExcludeScanForAll.Length -eq 0) {
                        $ExcludeAll = 0
                        continue
                    }
                    foreach ($piece in $ExcludeScanForAll) {
                        if ($testContent -like "*$piece*") {
                            $ExcludeFlag += 1
                        }
                    }
                    if ($ExcludeFlag -eq $ExcludeScanForAll.Length) {
                        $ExcludeAll += 1
                    }
                }
                if ($ExcludeAll -eq 0) {
                    $ScanTests += $test
                }
            }
        }
        $AllScenarioTests = $ScanTests
    } else {
        $AllScenarioTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -in $TestsRunGroups[$Scenario] }
    }
    return $AllScenarioTests
}


function Get-TestsForBuildScenario {
    param($ModuleBase, [switch]$Silent)
    # Invoke pester.groups.ps1 to know which tests to run
    . "$ModuleBase\tests\pester.groups.ps1"
    # retrieve all .Tests.
    $AllDbatoolsTests = Get-ChildItem -File -Path "$ModuleBase\tests\*.Tests.ps1"
    # exclude "disabled"
    $AllTests = $AllDbatoolsTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['disabled'] }
    # only in appveyor, disable uncooperative tests
    $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['appveyor_disabled'] }

    # Inspect special words
    $TestsToRunMessage = "$($env:APPVEYOR_REPO_COMMIT_MESSAGE) $($env:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED)"
    $TestsToRunRegex = [regex] '(?smi)\(do (?<do>[^)]+)\)'
    $TestsToRunMatch = $TestsToRunRegex.Match($TestsToRunMessage).Groups['do'].Value
    if ($TestsToRunMatch.Length -gt 0) {
        $TestsToRun = "*$TestsToRunMatch*"
        $AllTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -like $TestsToRun }
        if (-not($Silent)) {
            Write-Host -ForegroundColor DarkGreen "Commit message: Reduced to $($AllTests.Count) out of $($AllDbatoolsTests.Count) tests"
        }
        if ($AllTests.Count -eq 0) {
            throw "something went wrong, nothing to test"
        }
    } else {
        $TestsToRun = "*.Tests.*"
    }

    # do we have a scenario ?
    if ($env:SCENARIO) {
        # if so, do we have a group with tests to run ?
        if ($env:SCENARIO -in $TestsRunGroups.Keys) {
            $AllScenarioTests = Get-TestsForScenario -scenario $env:SCENARIO -AllTest $AllTests -Silent:$Silent
        } else {
            $AllTestsToExclude = @()
            $validScenarios = $TestsRunGroups.Keys | Where-Object { $_ -notin @('disabled', 'appveyor_disabled') }
            foreach ($k in $validScenarios) {
                $AllTestsToExclude += Get-TestsForScenario -scenario $k -AllTest $AllTests
            }
            $AllScenarioTests = $AllTests | Where-Object { $_ -notin $AllTestsToExclude }
        }
    } else {
        $AllScenarioTests = $AllTests
    }
    if (-not($Silent)) {
        Write-Host -ForegroundColor DarkGreen "Test Groups   : Reduced to $($AllScenarioTests.Count) out of $($AllDbatoolsTests.Count) tests"
    }
    # do we have a part ? (1/2, 2/2, etc)
    if ($env:PART) {
        try {
            [int]$num, [int]$denom = $env:PART.Split('/')
            if (-not($Silent)) {
                Write-Host -ForegroundColor DarkGreen "Test Parts    : part $($env:PART) on total $($AllScenarioTests.Count)"
            }
            #shuffle things a bit (i.e. with natural sorting most of the *get* fall into the first part, all the *set* in the last, etc)
            $AllScenarioTestsShuffled = $AllScenarioTests | Sort-Object -Property @{Expression = { $_.Name.Split('-')[-1].Replace('Dba', '') }; Ascending = $true}
            $scenarioParts = Split-ArrayInParts -array $AllScenarioTestsShuffled -parts $denom
            $AllScenarioTests = $scenarioParts[$num - 1] | Sort-Object -Property Name
        } catch {
        }
    }
    if ($AllTests.Count -eq 0 -and $AllScenarioTests.Count -eq 0) {
        throw "something went wrong, nothing to test"
    }
    return $AllScenarioTests
}