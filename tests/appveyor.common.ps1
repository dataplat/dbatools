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
        $testsThatDependOn = @()
        foreach ($t in $AllTests) {
            # get tests for other functions that rely upon rely upon the selected ones
            $testsThatDependOn += Get-AllTestsIndications -Path $t -ModuleBase $ModuleBase

        }
        $AllTests = (($testsThatDependOn + $AllTests) | Select-Object -Unique)
        # re-filter disabled tests that may have been picked up by dependency tracking
        $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['disabled'] }
        $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['appveyor_disabled'] }
        if (-not($Silent)) {
            Write-Host -ForegroundColor DarkGreen "Commit message: Extended to $($AllTests.Count) for all the dependencies"
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
            $AllScenarioTestsShuffled = $AllScenarioTests | Sort-Object -Property @{Expression = { $_.Name.Split('-')[-1].Replace('Dba', '') }; Ascending = $true }
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

function Get-TestIndications($Path, $ModuleBase, $eval) {
    # takes a test file path and figures out what to run for tests (i.e. functions that depend on this)
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
        # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
        $searchme = "$f "
        foreach ($f in $everything) {
            $source = $f.Definition
            $CBH = $CBHRex.match($source).Value
            # This fails very hard sometimes
            if ($source -and $CBH) {
                $cmdonly = $source.Replace($CBH, '')
                if ($cmdonly.contains($searchme)) {
                    $funcs += $f.Name
                }
            }
        }
    }
    $testpaths = @()
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\tests" -Filter '*.ps1'
    foreach ($f in $funcs) {
        # exclude always used functions ?!
        if ($f -in ('Connect-DbaInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
        # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
        $res = $allfiles | Where-Object { $_.Name -like "$($f).*Tests.ps1" }
        if ($res.count -gt 0) {
            $testpaths += $res.FullName
        }
    }
    foreach ($item in $testpaths) {
        $eval[$item] = 1
    }
    return $eval
}

function Get-AllTestsIndications($Path, $ModuleBase) {
    # takes a test file path and figures out what to run for tests (i.e. functions that depend on this, till the top level is reached)
    $baseTests = $Path
    $evaluated = @{ }
    $evaluated = Get-TestIndications -Path $baseTests -ModuleBase $ModuleBase -eval $evaluated
    $seen = @{ }
    while ($true) {
        $currKeys = @()
        foreach ($k in $evaluated.Keys) {
            $currKeys += $k
        }
        foreach ($key in $currKeys) {
            #write-host -fore Yellow "eval $key"
            if ($key -in $seen.Keys) {
                #write-host -fore Yellow "skipping $key, already seen"
            } else {
                $evaluated = Get-TestIndications -Path $key -ModuleBase $ModuleBase -eval $evaluated
                $seen[$key] = 1
            }
        }
        if ($evaluated.Keys.Count -eq $currKeys.Count) {
            break
        }
    }
    # add dbatools.Tests.ps1 always
    $evaluated["$ModuleBase\tests\dbatools.Tests.ps1"] = 1
    Get-Item $evaluated.GetEnumerator().Name
}