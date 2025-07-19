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

.EXAMPLE
.\appveyor.pester.ps1
Executes the test

.EXAMPLE
.\appveyor.pester.ps1 -Finalize
Finalizes the tests
#>
param (
    [switch]$Finalize,
    $PSVersion = $PSVersionTable.PSVersion.Major,
    $TestFile = "TestResultsPS$PSVersion.xml",
    $ProjectRoot = $env:APPVEYOR_BUILD_FOLDER,
    $ModuleBase = $ProjectRoot,
    [switch]$IncludeCoverage
)

# Move to the project root
Set-Location $ModuleBase
# required to calculate coverage
$global:dbatools_dotsourcemodule = $true
$dbatools_serialimport = $true

#imports the module making sure DLL is loaded ok
# Import Pester early to avoid loader deadlock
Write-Host "### DEBUG: Early Import-Module Pester 5"
Import-Module pester -RequiredVersion 5.6.1 -Verbose
Remove-Module pester
Write-Host "### DEBUG: Early Import-Module Pester 5 done"

#imports the module making sure DLL is loaded ok
# Import Pester early to avoid loader deadlock
Write-Host "### DEBUG: Early Import-Module Pester 4"
Import-Module pester -RequiredVersion 4.10.1 -Verbose
Write-Host "### DEBUG: Early Import-Module Pester 4 done"

Import-Module "$ModuleBase\dbatools.psd1"
#imports the psm1 to be able to use internal functions in tests
Import-Module "$ModuleBase\dbatools.psm1" -Force
# Force all SQL connections to trust the server certificate in CI
Set-DbatoolsInsecureConnection

Update-TypeData -AppendPath "$ModuleBase\xml\dbatools.types.ps1xml" -ErrorAction SilentlyContinue # ( this should already be loaded by dbatools.psd1 )
Start-Sleep 5

function Split-ArrayInParts($array, [int]$parts) {
    #splits an array in "equal" parts
    $size = $array.Length / $parts
    $counter = [pscustomobject] @{ Value = 0 }
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
        $res = $allfiles | Where-Object { $_.Name.Replace('.ps1', '') -eq $f }
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
        $filename = $_.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{ }
            $LineCount[$filename] = (Get-Content $_.File -Raw | Measure-Object -Line).Lines
        }
        $report['coverage'][$filename][$_.Line] = 1
    }

    $missed | ForEach-Object {
        $filename = $_.File.Replace("$ModuleBase\", '').Replace('\', '/')
        if ($filename -notin $report['coverage'].Keys) {
            $report['coverage'][$filename] = @{ }
            $LineCount[$filename] = (Get-Content $_.File | Measure-Object -Line).Lines
        }
        if ($_.Line -notin $report['coverage'][$filename].Keys) {
            #miss only if not already covered
            $report['coverage'][$filename][$_.Line] = 0
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

function Get-PesterTestVersion($testFilePath) {
    $testFileContent = Get-Content -Path $testFilePath -Raw
    if ($testFileContent -match '#Requires\s+-Module\s+@\{\s+ModuleName="Pester";\s+ModuleVersion="5\.') {
        return '5'
    }
    return '4'
}


if (-not $Finalize) {
    # Invoke appveyor.common.ps1 to know which tests to run
    . "$ModuleBase\tests\appveyor.common.ps1"
    $AllScenarioTests = Get-TestsForBuildScenario -ModuleBase $ModuleBase
}

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if (-not $Finalize) {
    Set-Variable ProgressPreference -Value SilentlyContinue
    Write-Host "### DEBUG: Entering test execution phase"
    if ($AllScenarioTests.Count -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Nothing to do in this scenario"
        return
    }
    # Remove any previously loaded pester module
    Remove-Module -Name pester -ErrorAction SilentlyContinue
    Write-Host "### DEBUG: Importing Pester 4"
    # Import pester 4
    Import-Module pester -RequiredVersion 4.10.1
    Write-Host "### DEBUG: Imported Pester 4"
    Write-Host -Object "appveyor.pester: Running with Pester Version $((Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version)" -ForegroundColor DarkGreen

    # Import dbatools modules and configure connection, after Pester is imported (for loader safety)
    Import-Module dbatools.library
    Import-Module C:\github\dbatools\dbatools.psd1
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register
    Write-Host -Object "========== Get-DbaManagementObject diagnostic (Pester 4) ==========" -ForegroundColor Yellow
    Get-DbaManagementObject | Format-List
    Write-Host -Object "========== End diagnostics ==========" -ForegroundColor Yellow

    # invoking a single invoke-pester consumes too much memory, let's go file by file
    $AllTestsWithinScenario = Get-ChildItem -File -Path $AllScenarioTests
    Write-Host "### DEBUG: After file gather, $($AllTestsWithinScenario.Count) files"
    #start the round for pester 4 tests
    $Counter = 0
    foreach ($f in $AllTestsWithinScenario) {
        $Counter += 1
        $PesterSplat = @{
            'Script'   = $f.FullName
            'Show'     = 'None'
            'PassThru' = $true
        }
        #get if this test should run on pester 4 or pester 5
        $pesterVersionToUse = Get-PesterTestVersion -testFilePath $f.FullName
        if ($pesterVersionToUse -eq '5') {
            # we're in the "region" of pester 4, so skip
            continue
        }

        #opt-in
        if ($IncludeCoverage) {
            $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
            $PesterSplat['CodeCoverage'] = $CoverFiles
            $PesterSplat['CodeCoverageOutputFile'] = "$ModuleBase\PesterCoverage$Counter.xml"
        }
        # Pester 4.0 outputs already what file is being ran. If we remove write-host from every test, we can time
        # executions for each test script (i.e. Executing Get-DbaFoo .... Done (40 seconds))
        $trialNo = 1
        while ($trialNo -le 3) {
            if ($trialNo -eq 1) {
                $appvTestName = $f.Name
            } else {
                $appvTestName = "$($f.Name), attempt #$trialNo"
            }
            Add-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome Running
            Write-Host "### DEBUG: Before Invoke-Pester $($f.FullName)"
            $PesterRun = Invoke-Pester @PesterSplat
            Write-Host "### DEBUG: After Invoke-Pester $($f.FullName)"
            $PesterRun | Export-Clixml -Path "$ModuleBase\PesterResults$PSVersion$Counter.xml"
            if ($PesterRun.FailedCount -gt 0) {
                $trialno += 1
                Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Failed" -Duration $PesterRun.Time.TotalMilliseconds
            } else {
                Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Passed" -Duration $PesterRun.Time.TotalMilliseconds
                break
            }
        }
    }

    #start the round for pester 5 tests
    # Remove any previously loaded pester module
    Remove-Module -Name pester -ErrorAction SilentlyContinue
    Write-Host "### DEBUG: Importing Pester 5"
    # Import pester 5
    Import-Module pester -RequiredVersion 5.6.1
    Write-Host "### DEBUG: Imported Pester 5"
    Write-Host -Object "appveyor.pester: Running with Pester Version $((Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version)" -ForegroundColor DarkGreen

    # Import dbatools modules and configure connection, after Pester is imported (for loader safety)
    Import-Module dbatools.library
    Import-Module C:\github\dbatools\dbatools.psd1
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register
    Write-Host -Object "========== Get-DbaManagementObject diagnostic (Pester 5) ==========" -ForegroundColor Yellow
    Get-DbaManagementObject | Format-List
    Write-Host -Object "========== End diagnostics ==========" -ForegroundColor Yellow

    $Counter = 0
    foreach ($f in $AllTestsWithinScenario) {
        $Counter += 1

        #get if this test should run on pester 4 or pester 5
        $pesterVersionToUse = Get-PesterTestVersion -testFilePath $f.FullName
        if ($pesterVersionToUse -eq '4') {
            # we're in the "region" of pester 5, so skip
            continue
        }
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
            Write-Host "### DEBUG: Before Invoke-Pester (Pester5) $($f.FullName)"
            $PesterRun = Invoke-Pester -Configuration $pester5config
            Write-Host "### DEBUG: After Invoke-Pester (Pester5) $($f.FullName)"
            Write-Host -Object "`rCompleted $($f.FullName) in $([int]$PesterRun.Duration.TotalMilliseconds)ms" -ForegroundColor Cyan
            $PesterRun | Export-Clixml -Path "$ModuleBase\Pester5Results$PSVersion$Counter.xml"
            if ($PesterRun.FailedCount -gt 0) {
                $trialno += 1
                Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Failed" -Duration $PesterRun.Duration.TotalMilliseconds
            } else {
                Update-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome "Passed" -Duration $PesterRun.Duration.TotalMilliseconds
                break
            }
        }
    }

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
            Set-Content -Path $errorFile -Value 'Uncomment line 245 in appveyor.pester.ps1 if needed'
        }
        if (-not (Test-Path $errorFile)) {
            Set-Content -Path $errorFile -Value 'None'
        }
        Compress-Archive -Path $msgFile, $errorFile -DestinationPath "dbatools_messages_and_errors.xml.zip" -ErrorAction Stop
        Remove-Item $msgFile
        Remove-Item $errorFile
    } catch {
        Write-Host -ForegroundColor Red "Message collection failed: $($_.Exception.Message)"
    }
} else {
    # Unsure why we're uploading so I removed it for now
    <#
    #If finalize is specified, check for failures and  show status
    $allfiles = Get-ChildItem -Path $ModuleBase\*Results*.xml | Select-Object -ExpandProperty FullName
    Write-Output "Finalizing results and collating the following files:"
    Write-Output ($allfiles | Out-String)
    #Upload results for test page
    Get-ChildItem -Path "$ModuleBase\TestResultsPS*.xml" | Foreach-Object {
        $Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
        $Source = $_.FullName
        Write-Output "Uploading files: $Address $Source"
        (New-Object System.Net.WebClient).UploadFile($Address, $Source)
        Write-Output "You can download it from https://ci.appveyor.com/api/buildjobs/$($env:APPVEYOR_JOB_ID)/tests"
    }
    #>
    #What failed? How many tests did we run ?
    $results = @(Get-ChildItem -Path "$ModuleBase\PesterResults*.xml" | Import-Clixml)
    #Publish the support package regardless of the outcome
    if (Test-Path $ModuleBase\dbatools_messages_and_errors.xml.zip) {
        Get-ChildItem $ModuleBase\dbatools_messages_and_errors.xml.zip | ForEach-Object { Push-AppveyorArtifact $_.FullName -FileName $_.Name }
    }
    #$totalcount = $results | Select-Object -ExpandProperty TotalCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $failedcount = 0
    $failedcount += $results | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    if ($failedcount -gt 0) {
        # pester 4 output
        $faileditems = $results | Select-Object -ExpandProperty TestResult | Where-Object { $_.Passed -notlike $True }
        if ($faileditems) {
            Write-Warning "Failed tests summary (pester 4):"
            $faileditems | ForEach-Object {
                $name = $_.Name
                [pscustomobject]@{
                    Describe = $_.Describe
                    Context  = $_.Context
                    Name     = "It $name"
                    Result   = $_.Result
                    Message  = $_.FailureMessage
                }
            } | Sort-Object Describe, Context, Name, Result, Message | Format-List
            throw "$failedcount tests failed."
        }
    }


    $results5 = @(Get-ChildItem -Path "$ModuleBase\Pester5Results*.xml" | Import-Clixml)
    $failedcount += $results5 | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    # pester 5 output
    $faileditems = $results5 | Select-Object -ExpandProperty Tests | Where-Object { $_.Passed -notlike $True }
    if ($faileditems) {
        Write-Warning "Failed tests summary (pester 5):"
        $faileditems | ForEach-Object {
            $name = $_.Name
            [pscustomobject]@{
                Path    = $_.Path -Join '/'
                Name    = "It $name"
                Result  = $_.Result
                Message = $_.ErrorRecord -Join ""
            }
        } | Sort-Object Path, Name, Result, Message | Format-List
        throw "$failedcount tests failed."
    }

    #opt-in
    if ($IncludeCoverage) {
        # for now, this manages recreating a codecov-ingestable format for pester 4. Pester 5 uses JaCoCo natively, which
        # codecov accepts ... there's only the small matter that we generate one coverage per run, and there's a run per test file
        # and there's no native-powershelly-way to merge JaCoCo reports. Let's start small, and complicate our lives farther down the line.
        $CodecovReport = Get-CodecovReport -Results $results -ModuleBase $ModuleBase
        $CodecovReport | ConvertTo-Json -Depth 4 -Compress | Out-File -FilePath "$ModuleBase\PesterResultsCoverage.json" -Encoding utf8
    }
}