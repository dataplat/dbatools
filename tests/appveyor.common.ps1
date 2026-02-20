function Get-TestsForScenario {
    param($Scenario, $AllTests, [switch]$Silent)

    # does this scenario run an 'autodetect' ?
    if ($TestsRunGroups[$Scenario].StartsWith('autodetect_')[0]) {
        # exclude any test specifically tied to a non-autodetect or version specific scenario
        $TiedFunctions = ($TestsRunGroups.GetEnumerator() | Where-Object { $_.Value -notlike 'autodetect_*' -and $_.Name -notlike '20*' }).Value
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

    # Check if we're in a Pull Request and auto-detect changed files
    $IsInPullRequest = $null -ne $env:APPVEYOR_PULL_REQUEST_NUMBER

    if ($IsInPullRequest) {
        if (-not($Silent)) {
            Write-Host -ForegroundColor DarkGreen "...We're in a PR"
        }
        try {
            # Get the list of changed files in this PR compared to the base branch
            $targetBranch = if ($env:APPVEYOR_REPO_BRANCH) { "origin/$env:APPVEYOR_REPO_BRANCH" } else { 'origin/development' }
            $ChangedFiles = git diff --name-only "$targetBranch...HEAD" 2>$null

            if (-not($Silent)) {
                Write-Host -ForegroundColor DarkGreen '...Changed files are: '
                foreach ($cmd in $ChangedFiles) {
                    Write-Host -ForegroundColor DarkGreen "...  - $cmd"
                }
            }


            if ($ChangedFiles) {
                # Track what types of files changed
                $changedCommands = @()
                $changedTests = @()

                foreach ($file in $ChangedFiles) {
                    # Check for changes to public commands
                    if ($file -like 'public/*.ps1') {
                        $commandName = Split-Path $file -Leaf | ForEach-Object { $_ -replace '\.ps1$', '' }
                        $changedCommands += $commandName
                    }
                    # Check for changes to private functions
                    elseif ($file -like 'private/functions/*.ps1') {
                        $functionName = Split-Path $file -Leaf | ForEach-Object { $_ -replace '\.ps1$', '' }
                        $changedCommands += $functionName
                    }
                    # Check for direct changes to test files
                    elseif ($file -like 'tests/*.Tests.ps1') {
                        $testName = Split-Path $file -Leaf
                        $changedTests += $testName
                    }
                }

                # Build list of tests to run based on changed commands
                $testsForChangedFiles = @()

                if ($changedCommands.Count -gt 0) {
                    # Find test files matching the changed commands
                    foreach ($cmd in $changedCommands) {
                        $matchingTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -eq $cmd }
                        $testsForChangedFiles += $matchingTests
                    }
                }

                # Add directly changed test files
                if ($changedTests.Count -gt 0) {
                    foreach ($testFile in $changedTests) {
                        $matchingTest = $AllTests | Where-Object { $_.Name -eq $testFile }
                        if ($matchingTest) {
                            $testsForChangedFiles += $matchingTest
                        }
                    }
                }

                if ($testsForChangedFiles.Count -gt 0) {
                    $AllTests = $testsForChangedFiles | Select-Object -Unique

                    if (-not($Silent)) {
                        Write-Host -ForegroundColor DarkGreen "PR Detection: Reduced to $($AllTests.Count) tests based on changed files"
                    }

                    # Expand to include dependencies (same as commit message approach)
                    $testsThatDependOn = @()
                    foreach ($t in $AllTests) {
                        $testsThatDependOn += Get-AllTestsIndications -Path $t -ModuleBase $ModuleBase
                    }
                    $AllTests = ($testsThatDependOn + $AllTests) | Group-Object -Property FullName | ForEach-Object { $_.Group | Select-Object -First 1 }

                    # Re-filter disabled tests that may have been picked up by dependency tracking
                    $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['disabled'] }
                    $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['appveyor_disabled'] }

                    if (-not($Silent)) {
                        Write-Host -ForegroundColor DarkGreen "PR Detection: Extended to $($AllTests.Count) tests including dependencies"
                    }
                }
            }
        } catch {
            # If auto-detection fails, fall through to commit message check
            if (-not($Silent)) {
                Write-Host -ForegroundColor Yellow "PR Detection: Auto-detection failed, falling back to commit message: $($_.Exception.Message)"
            }
        }
    }

    # Inspect special words (commit message override)
    $TestsToRunMessage = "$($env:APPVEYOR_REPO_COMMIT_MESSAGE) $($env:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED)"
    $TestsToRunRegex = [regex] '(?smi)\(do (?<do>[^)]+)\)'
    $TestsToRunMatch = $TestsToRunRegex.Match($TestsToRunMessage).Groups['do'].Value
    if ($TestsToRunMatch.Length -gt 0) {
        # Support comma-separated multiple commands/patterns
        $patterns = $TestsToRunMatch -split ',' | ForEach-Object { $_.Trim() }
        $AllTests = $AllTests | Where-Object {
            $testName = ($_.Name -replace '\.Tests\.ps1$', '')
            $matched = $false
            foreach ($pattern in $patterns) {
                # Support exact match with = prefix: (do =dbatools)
                if ($pattern -match '^=(.+)$') {
                    $exactPattern = $Matches[1]
                    if ($testName -eq $exactPattern) {
                        $matched = $true
                        break
                    }
                } elseif ($testName -like "*$pattern*") {
                    $matched = $true
                    break
                }
            }
            $matched
        }
        if (-not($Silent)) {
            Write-Host -ForegroundColor DarkGreen "Commit message: Reduced to $($AllTests.Count) out of $($AllDbatoolsTests.Count) tests"
        }
        $testsThatDependOn = @()
        if ($AllTests.Count -gt 0) {
            foreach ($t in $AllTests) {
                # get tests for other functions that rely upon rely upon the selected ones
                $testsThatDependOn += Get-AllTestsIndications -Path $t -ModuleBase $ModuleBase

            }
        } else {
            # No direct matches - fall back to dbatools.Tests.ps1 only
            if (-not($Silent)) {
                Write-Host -ForegroundColor DarkGreen 'Commit message: No direct test matches, falling back to dbatools.Tests.ps1'
            }
            $testsThatDependOn += Get-Item "$ModuleBase\tests\dbatools.Tests.ps1"
        }
        $AllTests = ($testsThatDependOn + $AllTests) | Group-Object -Property FullName | ForEach-Object { $_.Group | Select-Object -First 1 }
        # re-filter disabled tests that may have been picked up by dependency tracking
        $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['disabled'] }
        $AllTests = $AllTests | Where-Object { ($_.Name -replace '^([^.]+)(.+)?.Tests.ps1', '$1') -notin $TestsRunGroups['appveyor_disabled'] }
        if (-not($Silent)) {
            Write-Host -ForegroundColor DarkGreen "Commit message: Extended to $($AllTests.Count) for all the dependencies"
        }
        if ($AllTests.Count -eq 0) {
            throw 'something went wrong, nothing to test'
        }
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
            #shuffle things a bit (i.e. with natural sorting most of the *get* fall into the first part, all the *set* in the last, etc)
            $AllScenarioTestsShuffled = $AllScenarioTests | Sort-Object -Property @{Expression = { $_.Name.Split('-')[-1].Replace('Dba', '') }; Ascending = $true }
            $scenarioParts = Split-ArrayInParts -array $AllScenarioTestsShuffled -parts $denom
            $AllScenarioTests = $scenarioParts[$num - 1] | Sort-Object -Property Name
            if (-not($Silent)) {
                Write-Host -ForegroundColor DarkGreen "Test Parts    : part $($env:PART) with $($AllScenarioTests.Count)"
            }
        } catch {
        }
    }
    if ($AllTests.Count -eq 0 -and $AllScenarioTests.Count -eq 0) {
        throw 'something went wrong, nothing to test'
    }
    return $AllScenarioTests
}

function Get-TestIndications {
    # takes a test file path and figures out what to run for tests (i.e. functions that depend on this)
    param($Path, $ModuleBase, $ExportedCommands, $AllFiles, $cmdDef)
    $everyFunction = $ExportedCommands.Name
    $funcs = @()
    $leaf = Split-Path $path -Leaf
    # assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
    # but allowing also Get-DbaFoo.one.Tests.ps1 and Get-DbaFoo.two.Tests.ps1
    $func_name += ($leaf -Replace '^([^.]+)(.+)?.Tests.ps1', '$1')
    if ($func_name -in $everyFunction) {
        $funcs += $func_name
        $f = $ExportedCommands | Where-Object Name -eq $func_name
        # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
        $searchme = "$f "
        foreach ($f in $ExportedCommands) {
            $cmdOnly = $cmdDef[$f.Name]
            if ($cmdonly.Contains($searchme)) {
                $funcs += $f.Name
            }
        }
    }
    $testpaths = @()
    foreach ($f in $funcs) {
        # exclude always used functions ?!
        if ($f -in ('Connect-DbaInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
        # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
        $res = $allfiles | Where-Object { $_.Name -like "$($f).*Tests.ps1" }
        if ($res.Count -gt 0) {
            $testpaths += $res.FullName
        }
    }
    return ($testpaths | Sort-Object -Unique)
}

function Get-AllTestsIndications($Path, $ModuleBase) {
    # takes a test file path and figures out what to run for tests (i.e. functions that depend on this, till the top level is reached)
    $baseTestFile = $Path
    # prepare empty cache
    $testIndicationsResultCache = @{ }
    $testTreeRepresentation = @()

    $exportedCommands = (Get-Module dbatools).ExportedCommands.Values

    #prepare definitions to look up
    $cmdDef = Get-PreparedCommandDefinitions -ExportedCommands $exportedCommands

    # get all test files once and for all, so we don't have to do it every time we look for a dependency
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\tests" -Filter '*.ps1'

    $evaluated = Get-TestIndications -Path $baseTestFile -ModuleBase $ModuleBase -ExportedCommands $exportedCommands -AllFiles $allfiles -cmdDef $cmdDef
    $testIndicationsResultCache[$baseTestFile] = $evaluated

    foreach ($p in $evaluated) {
        $testTreeRepresentation += [pscustomobject]@{
            Source    = Get-FunctionNameFromTestFile $baseTestFile
            DependsOn = Get-FunctionNameFromTestFile $p
            Level     = 0
        }
    }

    $x = 0
    while ($true) {
        $x += 1
        $discoveredDependencies = $testIndicationsResultCache.Keys.Count
        $currKeys = @()
        foreach ($k in $testIndicationsResultCache.Keys) {
            foreach ($dep in $testIndicationsResultCache[$k]) {
                $currKeys += $dep
            }
        }

        foreach ($key in $currKeys) {
            if ($key -notin $testIndicationsResultCache.Keys) {
                $evaluated = Get-TestIndications -Path $key -ModuleBase $ModuleBase -ExportedCommands $exportedCommands -AllFiles $allfiles -cmdDef $cmdDef
                $testIndicationsResultCache[$key] = $evaluated
                foreach ($p in $evaluated) {
                    $testTreeRepresentation += [pscustomobject]@{
                        Source    = Get-FunctionNameFromTestFile $key
                        DependsOn = Get-FunctionNameFromTestFile $p
                        Level     = $x
                    }
                }
            }
        }
        if ($testIndicationsResultCache.Keys.Count -eq $discoveredDependencies) {
            # didn't discover anything new, so we can stop here
            break
        }
    }
    # add dbatools.Tests.ps1 always

    $returnValue = @{}
    $returnValue["$ModuleBase\tests\dbatools.Tests.ps1"] = 1
    foreach ($k in $testIndicationsResultCache.Keys) {
        $returnValue[$k] = 1
        foreach ($dep in $testIndicationsResultCache[$k]) {
            $returnValue[$k] = 1
        }
    }

    # for users in need of debugging, uncomment the following lines
    #$testTreeRepresentation | Sort Level,Source,DependsOn | Format-Table
    #Show-DependencyTree -Node (Get-FunctionNameFromTestFile $baseTestFile) -Data $testTreeRepresentation

    Get-Item $returnValue.GetEnumerator().Name
}

function Get-PreparedCommandDefinitions {
    param($ExportedCommands)
    # prepares in one sweep the "source code" of all the commands
    # so it can be searched for dependencies within
    $CBHRex = [regex]'(?smi)<#(.*)#>'
    $cmdDef = @{}
    foreach ($f in $ExportedCommands) {
        $rawSource = $f.Definition
        $CBH = $CBHRex.match($rawSource).Value
        # This fails very hard sometimes
        if ($rawSource -and $CBH) {
            $runningCode = $rawSource.Replace($CBH, '')
            $cmdDef[$f.Name] = $runningCode
        } else {
            $cmdDef[$f.Name] = ''
        }
    }
    return $cmdDef
}

function Get-FunctionNameFromTestFile($testFilePath) {
    $leaf = Split-Path $testFilePath -Leaf
    return $leaf.Replace('.Tests.ps1', '')
}

function Show-DependencyTree {
    # helper function to show the dependency tree for easier debugging
    param (
        [string]$Node,
        [object[]]$Data,
        [string]$Prefix = '',
        [bool]$IsLast = $true,
        [System.Collections.Generic.HashSet[string]]$Visited =
        (New-Object 'System.Collections.Generic.HashSet[string]')
    )

    if ($Prefix) {
        Write-Host ('{0}{1}{2}' -f $Prefix, ($(if ($IsLast) { '\-- ' } else { '|- ' })), $Node)
    } else {
        Write-Host $Node
    }

    if (-not $Visited.Add($Node)) {
        return
    }

    $children = @(
        $Data |
        Where-Object {
            $_.Source -eq $Node -and $_.DependsOn -ne $_.Source
        } |
        Select-Object -ExpandProperty DependsOn -Unique |
        Sort-Object
    )

    if ($children.Count -eq 0) {
        return
    }

    $nextPrefix = $Prefix + ($(if ($IsLast) { '   ' } else { '|  ' }))

    for ($i = 0; $i -lt $children.Count; $i++) {
        Show-DependencyTree `
            -Node $children[$i] `
            -Data $Data `
            -Prefix $nextPrefix `
            -IsLast ($i -eq $children.Count - 1) `
            -Visited $Visited
    }
}
