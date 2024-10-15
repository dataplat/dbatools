<#
.SYNOPSIS
This script will invoke Pester tests, then serialize XML results and pull them in appveyor.yml

.DESCRIPTION
Internal function that creates SMO server object.

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
#imports the psm1 to be able to use internal functions in tests
Import-Module "$ModuleBase\dbatools.psm1" -Force
#imports the module making sure DLL is loaded ok
Import-Module "$ModuleBase\dbatools.psd1"

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

    $LineCount = @{ }
    foreach ($result in $Results) {
        $analyzed = $result.CodeCoverage.AnalyzedFiles
        $missed = $result.CodeCoverage.MissedLines
        $hit = $result.CodeCoverage.HitLines

        foreach ($file in $analyzed) {
            $filename = $file.Replace("$ModuleBase\", '').Replace('\', '/')
            if ($filename -notin $report['coverage'].Keys) {
                $report['coverage'][$filename] = @{ }
                $LineCount[$filename] = (Get-Content $file | Measure-Object -Line).Lines
            }

            $hitLines = $hit[$file]
            $missedLines = $missed[$file]

            foreach ($line in $hitLines) {
                $report['coverage'][$filename][$line] = 1
            }

            foreach ($line in $missedLines) {
                if ($line -notin $report['coverage'][$filename].Keys) {
                    $report['coverage'][$filename][$line] = 0
                }
            }
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

function Send-CodecovReport($CodecovReport) {
    $params = @{ }
    $params['branch'] = $env:APPVEYOR_REPO_BRANCH
    $params['service'] = "appveyor"
    $params['job'] = $env:APPVEYOR_ACCOUNT_NAME
    if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_PROJECT_SLUG }
    if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_BUILD_VERSION }
    $params['build'] = $env:APPVEYOR_JOB_ID
    $params['pr'] = $env:APPVEYOR_PULL_REQUEST_NUMBER
    $params['slug'] = $env:APPVEYOR_REPO_NAME
    $params['commit'] = $env:APPVEYOR_REPO_COMMIT
    Add-Type -AssemblyName System.Web
    $CodeCovParams = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    $params.GetEnumerator() | Where-Object Value | ForEach-Object { $CodeCovParams.Add($_.Name, $_.Value) }
    $Request = [System.UriBuilder]('https://codecov.io/upload/v2')
    $Request.Query = $CodeCovParams.ToString()
    Invoke-RestMethod -Uri $Request.Uri -Method Post -InFile $CodecovReport -ContentType 'multipart/form-data'
}


if (-not $Finalize) {
    # Invoke appveyor.common.ps1 to know which tests to run
    . "$ModuleBase\tests\appveyor.common.ps1"
    $AllScenarioTests = Get-TestsForBuildScenario -ModuleBase $ModuleBase
}

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if (-not $Finalize) {
    Import-Module Pester
    Write-Host -Object "appveyor.pester: Running with Pester Version $((Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version)" -ForegroundColor DarkGreen
    Set-Variable ProgressPreference -Value SilentlyContinue
    if ($AllScenarioTests.Count -eq 0) {
        Write-Host -ForegroundColor DarkGreen "Nothing to do in this scenario"
        return
    }
    # invoking a single invoke-pester consumes too much memory, let's go file by file
    $AllTestsWithinScenario = Get-ChildItem -File -Path $AllScenarioTests
    $Counter = 0
    foreach ($f in $AllTestsWithinScenario) {
        $Counter += 1
        $PesterConfig = New-PesterConfiguration
        $PesterConfig.Run.Path = $f.FullName
        $PesterConfig.Run.PassThru = $true
        $PesterConfig.Output.Verbosity = 'None'

        if ($IncludeCoverage) {
            $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
            $PesterConfig.CodeCoverage.Enabled = $true
            $PesterConfig.CodeCoverage.Path = $CoverFiles
            $PesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
            $PesterConfig.CodeCoverage.OutputPath = "$ModuleBase\PesterCoverage$Counter.xml"
        }

        $trialNo = 1
        while ($trialNo -le 3) {
            if ($trialNo -eq 1) {
                $appvTestName = $f.Name
            } else {
                $appvTestName = "$($f.Name), attempt #$trialNo"
            }
            Add-AppveyorTest -Name $appvTestName -Framework NUnit -FileName $f.FullName -Outcome Running
            $PesterRun = Invoke-Pester -Configuration $PesterConfig
            $PesterRun | Export-Clixml -Path "$ModuleBase\PesterResults$PSVersion$Counter.xml"
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
    # Finalize is specified, check for failures and show status
    $results = @(Get-ChildItem -Path "$ModuleBase\PesterResults*.xml" | Import-Clixml)
    #Publish the support package regardless of the outcome
    if (Test-Path $ModuleBase\dbatools_messages_and_errors.xml.zip) {
        Get-ChildItem $ModuleBase\dbatools_messages_and_errors.xml.zip | ForEach-Object { Push-AppveyorArtifact $_.FullName -FileName $_.Name }
    }
    $failedcount = $results | ForEach-Object { $_.FailedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    if ($failedcount -gt 0) {
        $faileditems = $results | ForEach-Object { $_.Tests | Where-Object Result -eq 'Failed' }
        if ($faileditems) {
            Write-Warning "Failed tests summary:"
            $faileditems | ForEach-Object {
                [pscustomobject]@{
                    Describe = $_.Describe
                    Context  = $_.Context
                    Name     = "It $($_.Name)"
                    Result   = $_.Result
                    Message  = $_.ErrorRecord.DisplayErrorMessage
                }
            } | Sort-Object Describe, Context, Name, Result, Message | Format-List
            throw "$failedcount tests failed."
        }
    }
    #opt-in
    if ($IncludeCoverage) {
        $CodecovReport = Get-CodecovReport -Results $results -ModuleBase $ModuleBase
        $CodecovReport | ConvertTo-Json -Depth 4 -Compress | Out-File -FilePath "$ModuleBase\PesterResultsCoverage.json" -Encoding utf8
    }
}